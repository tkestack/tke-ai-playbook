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
