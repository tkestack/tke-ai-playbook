#!/bin/bash
set -e

check_crane_installed() {
  kubectl get -n kube-system deploy crane-scheduler-controller &>/dev/null
  return $?
}

create_provider_config() {
  local secret_id="$1"
  local secret_key="$2"

  cat >provider.tf <<EOF
terraform {
  required_providers {
    tencentcloud = {
      source = "tencentcloudstack/tencentcloud"
      version = "1.82.6"
    }
  }
}

provider "tencentcloud" {
  region = "$region"
  secret_id  = "$secret_id"
  secret_key = "$secret_key"
}
EOF
}

create_main_config() {
  local cluster_id="$1"

  cat >main.tf <<EOF
resource "tencentcloud_kubernetes_addon" "crane" {
  cluster_id = "$cluster_id"
  addon_name = "cranescheduler"
  addon_version = "1.6.4"
}
EOF
}

init_terraform() {
  echo "Initializing Terraform..."
  terraform init
  if [ $? -ne 0 ]; then
    echo "Terraform initialization failed"
    rm -rf .terraform*
    exit 1
  fi
}

apply_config() {
  echo "Applying CraneScheduler configuration..."
  terraform apply -auto-approve
  if [ $? -ne 0 ]; then
    echo "Terraform apply failed"
    exit 1
  fi
}

install_cranescheduler() {
  if check_crane_installed; then
    read -p "CraneScheduler is already installed. Reinstall? (y/n): " reinstall
    if [[ "$reinstall" != "y" && "$reinstall" != "Y" ]]; then
      echo "Skipping CraneScheduler installation"
      return 0
    fi
  fi

  echo "Starting CraneScheduler installation"

  echo -e "\nPlease obtain your TencentCloud API credentials:"
  echo "1. Visit https://console.cloud.tencent.com/cam/capi"
  echo "2. Create or use existing SecretId/SecretKey"
  read -p "Enter Secret ID: " secret_id
  read -p "Enter Secret Key: " secret_key


  echo -e "\nPlease obtain your ClusterInfo:"
  read -p "Enter Kubernetes Cluster ID: " cluster_id
  echo -e "\nVisit https://cloud.tencent.com/document/product/457/44787#MainlandChina to find region"
  read -p "Enter cluster region(default: ap-guangzhou): " region

  export TENCENTCLOUD_SECRET_ID="$secret_id"
  export TENCENTCLOUD_SECRET_KEY="$secret_key"

  create_provider_config "$secret_id" "$secret_key"
  terraform init -upgrade
  create_main_config "$cluster_id"
  apply_config

  echo "Verifying installation..."
  if check_crane_installed; then
    echo "CraneScheduler installed successfully"
  else
    echo "CraneScheduler installation failed - resource not found"
    echo "Checking Terraform state..."
    terraform show
    exit 1
  fi
}

echo "==== CraneScheduler Installation ===="
bash install-terraform.sh
install_cranescheduler
echo "==== Install CraneScheduler Complete ===="
