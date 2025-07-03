#!/bin/bash
# GPU Utilization Report
# Usage: ./gpu-utilization.sh

# Get all nodes with GPU capacity
gpu_nodes=$(kubectl get nodes -l node.kubernetes.io/instance-type!=eklet  -o json | jq -r '.items[] | select(.status.capacity["nvidia.com/gpu"] or .status.capacity["amd.com/gpu"]) | .metadata.name')

# Exit if no GPU nodes found
if [ -z "$gpu_nodes" ]; then
  echo "No GPU-enabled nodes found in the cluster"
  exit 1
fi

# Header
echo "-----------------------------------------------------------------------------"
printf "%-40s | %-12s | %-14s | %-14s\n" \
  "Node" "GPU Capacity" "Allocated GPUs" "Utilization (%)"

# Process each GPU node
for node in $gpu_nodes; do
  # Get GPU capacity
  gpu_capacity=$(kubectl get node $node -o json | jq -r '.status.capacity["nvidia.com/gpu"] // .status.capacity["amd.com/gpu"]')
  
  # Get allocated GPUs
  allocated_gpu=$(kubectl describe node $node | awk '
    BEGIN { found = 0 }
    /Allocated resources:/ { found = 1 }
    /Events:/ { found = 0 }
    found && $0 ~ /\.com\/gpu/ {
      gsub(/[()]/, "", $3);
      split($3, parts, /(\/|:)/);
      print parts[1];
      exit
    }
  ')
  
  # Normalize values
  if [[ -z "$gpu_capacity" || "$gpu_capacity" =~ [^0-9.] ]]; then
    gpu_capacity_num=0
  else
    gpu_capacity_num=$gpu_capacity
  fi
  
  if [[ -z "$allocated_gpu" || "$allocated_gpu" == "<none>" ]]; then
    allocated_gpu=0
    allocated_gpu_num=0
  else
    allocated_gpu_num=$allocated_gpu
  fi

  # Calculate utilization percentage
  if (( $(echo "$gpu_capacity_num > 0" | bc -l) )); then
    utilization=$(echo "scale=2; $allocated_gpu_num * 100 / $gpu_capacity_num" | bc)
  else
    utilization="N/A"
  fi

  # Print node information
  printf "%-40s | %-12s | %-14s | %-14s\n" \
    "$node" \
    "${gpu_capacity:-N/A}" \
    "${allocated_gpu:-0}" \
    "${utilization:-N/A}"
done
echo "-----------------------------------------------------------------------------"
