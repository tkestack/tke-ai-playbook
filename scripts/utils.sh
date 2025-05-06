#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


# Function to print green message
LogGreen() {
  echo -e "${GREEN}$@${NC}"
}

# Function to print yellow message
LogYellow() {
  echo -e "${YELLOW}$@${NC}"
}

# Function to print red message
LogRed() {
  echo -e "${RED}$@${NC}"
}

# Function to print blue message
LogBlue() {
  echo -e "${BLUE}$@${NC}"
}

# Function to print cyan message
LogCyan() {
  echo -e "${CYAN}$@${NC}"
}

# Function to print debug message
Debug() {
  if [[ ${DEBUG:-""} == "true" ]]; then
    echo -e "${BLUE}  [DEBUG]${NC} $@"
  fi
}

# Function to print info message
Info() {
  echo -e "${CYAN}   [INFO]${NC} $@"
}

# Function to print warning message
Warn() {
  echo -e "${YELLOW}   [WARN]${NC} $@"
}

# Function to print error message
Error() {
  echo -e "${RED}  [ERROR]${NC} $@"
}

# Function to print success message
Success() {
  echo -e "${GREEN}[SUCCESS]${NC} $@"
}

# Function to print fatal message and exit
Fatal() {
  echo -e "${RED}  [FATAL]${NC} $@"
  exit 1
}

# Function to print confirm message
Confirm() {
  echo -n -e "${BLUE}[CONFIRM]${NC} "
  read -p "$@" -r
}

# Function to check if a command exists
CommandExists() {
  command -v "$1" >/dev/null 2>&1
}

# Function to check if commands exists
# Usage: MustRequirements "command1" "command2" "command3"
# If any of the command is not installed or not in PATH, it will exit with error
MustRequirements() {
  for cmd in "$@"; do
    if ! CommandExists "$cmd"; then
      Fatal "'$cmd' is not installed or not in PATH"
    else
      Debug "'$cmd' is avaliable"
    fi
  done
}

MustConnectToKubernetesCluster() {
  if ! kubectl get nodes &>/dev/null; then
    Fatal "Cannot connect to kubernetes cluster, please make sure you're connected to the cluster and try again"
  fi
}

CheckKubernetesClusterHaveEnoughGPUResources() {
  # Step 1: Get all nodes with GPU resources (by checking the `nvidia.com/gpu` resource)
  gpu_nodes=$(kubectl get nodes -o json | jq -r '.items | map(select(.status.allocatable."nvidia.com/gpu" != null) | .metadata.name) | join(" ")')
  # If no GPU nodes, exit directly.
  if [ -z "${gpu_nodes}" ]; then
    Fatal "No nodes with GPU resources found."
  fi
  Info "Found $(echo ${gpu_nodes} | wc -w | xargs) nodes with GPU resources"

  cnt=0
  # Step 2: Traverse each GPU node, check the remaining resources
  for node in ${gpu_nodes}; do
    # fetch the total number of GPUs on the node
    alloc_gpu=$(kubectl get node ${node} -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')

    # fetch the total used GPUs on the node
    used_gpu=$(kubectl get pods -A --field-selector spec.nodeName=${node} -o jsonpath='{range .items[*]}{.spec.containers[*].resources.requests.nvidia\.com/gpu}{"\n"}{end}' | awk '{sum += $1} END {print sum}')

    # compute the remaining GPUs on the node (handle empty values)
    used_gpu=${used_gpu:-0}
    remain_gpu=$((alloc_gpu - used_gpu))
    if [[ ${remain_gpu} -ge $2 ]]; then
      cnt=$((cnt+1))
      Info "Found node '${node}' has ${remain_gpu} GPU(s) available, required: $1, avaliable: ${cnt}"
      if [[ ${cnt} -ge $1 ]]; then
        Info "Found ${cnt} node(s) with enough GPU resources, ready to deploy"
        break
      fi
    fi
  done
  
  if [[ ${cnt} -lt $1 ]]; then
    Error "Not enough GPU available, need $2 GPU(s) resource in $1 node, please check the GPU resources on the nodes"
    Confirm "Do you want to see the GPU resources usage on the nodes? (y/n): "
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      for node in ${gpu_nodes}; do
        # fetch the total number of GPUs on the node
        alloc_gpu=$(kubectl get node ${node} -o jsonpath='{.status.allocatable.nvidia\.com/gpu}')

        # fetch the total used GPUs on the node
        used_gpu=$(kubectl get pods -A --field-selector spec.nodeName=${node} -o jsonpath='{range .items[*]}{.spec.containers[*].resources.requests.nvidia\.com/gpu}{"\n"}{end}' | awk '{sum += $1} END {print sum}')

        # compute the remaining GPUs on the node (handle empty values)
        used_gpu=${used_gpu:-0}
        remain_gpu=$((alloc_gpu - used_gpu))
        # pr
        echo "Node: ${node}"
        echo "  Allocatable GPU: ${alloc_gpu}"
        echo "  Remaining GPU: ${remain_gpu}"
        if [[ ${alloc_gpu} -eq ${remain_gpu} ]]; then
          echo "  GPU consumers: null"
        else
          echo "  GPU Consumers:"
          kubectl get pods -A --field-selector spec.nodeName=${node} -o json | jq -r '.items[] | select(.spec.containers[].resources.requests."nvidia.com/gpu" != null) | "    Namespace: \(.metadata.namespace), Pod: \(.metadata.name), GPU Request: \(.spec.containers[].resources.requests."nvidia.com/gpu")"'
        fi
        echo "----------------------------------------"
      done
    fi
    exit 1
  fi
}