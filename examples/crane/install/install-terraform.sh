#!/bin/bash
set -e

install_terraform() {
    # Check if Terraform is already installed
    if command -v terraform &> /dev/null; then
        echo "Terraform is already installed"
        terraform -version
        return
    fi

    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    case $OS in
        darwin*)
            echo "Installing Terraform on macOS..."
            if ! command -v brew &> /dev/null; then
                echo "Homebrew not found! Please install manually from:"
                echo "https://developer.hashicorp.com/terraform/install"
                exit 1
            fi
            brew tap hashicorp/tap
            brew install hashicorp/tap/terraform
            ;;
        linux*)
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case $ID in
                    ubuntu|debian)
                        echo "Installing Terraform on Ubuntu/Debian..."
                        sudo apt-get update
                        sudo apt-get install -y gpg wget
                        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                        sudo apt update
                        sudo apt install -y terraform
                        ;;
                    centos|rhel)
                        echo "Installing Terraform on CentOS/RHEL..."
                        sudo yum install -y yum-utils
                        sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
                        sudo yum install -y terraform
                        ;;
                    *)
                        echo "Unsupported Linux distribution. Please install manually from:"
                        echo "https://developer.hashicorp.com/terraform/install"
                        exit 1
                        ;;
                esac
            else
                echo "Unsupported OS. Please install manually from:"
                echo "https://developer.hashicorp.com/terraform/install"
                exit 1
            fi
            ;;
        *)
            echo "Unsupported OS. Please install manually from:"
            echo "https://developer.hashicorp.com/terraform/install"
            exit 1
            ;;
    esac

    # Add to PATH for current session
    case $OS in
        linux*|darwin*)
            TERRAFORM_PATH=$(dirname $(which terraform))
            if [[ ":$PATH:" != *":$TERRAFORM_PATH:"* ]]; then
                export PATH="$PATH:$TERRAFORM_PATH"
                echo "Added Terraform to PATH for current session"
            fi
            ;;
        *)
            echo "For Windows, please add Terraform directory to your system PATH manually"
            ;;
    esac

    echo "Terraform installed successfully! Version:"
    terraform -version
}

install_terraform
