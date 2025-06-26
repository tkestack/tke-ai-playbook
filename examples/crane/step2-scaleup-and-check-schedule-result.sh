#/bin/bash

# Current timestamp function
timestamp() {
  date +"%T"
}

get_node_gpu_packing_rate() {
  local node=$1
  
  node_json=$(kubectl get node $node -o json 2>/dev/null)
  
  gpu_capacity=$(kubectl get node $node -o json | jq -r '.status.capacity["nvidia.com/gpu"] // .status.capacity["amd.com/gpu"]')
  
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
  echo "$utilization" 
}

show_highest_gpu_node() {
  highest_node=""
  highest_rate=0
  found_gpu_nodes=0
  
  nodes=($(kubectl get nodes -o json | jq -r '.items[].metadata.name'))
  
  for node in "${nodes[@]}"; do
    utilization=$(get_node_gpu_packing_rate "$node")
    
    if [[ "$utilization" =~ ^[0-9.]+$ ]]; then
      found_gpu_nodes=1
      
      if (( $(echo "$utilization > $highest_rate" | bc -l) )); then
        highest_rate=$utilization
        highest_node=$node
      fi
    fi
  done
  
  if (( found_gpu_nodes == 0 )); then
    echo "  No GPU-enabled nodes found"
  elif [[ -n "$highest_node" ]]; then
    echo "Highest GPU packing node: $highest_node ($highest_rate%)"
  else
    echo -e "\nNo nodes with GPU utilization data"
  fi
}

show_pod_scheduling() {
  local message=$1
  
  kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " scheduled on " + .spec.nodeName' | \
  while read -r pod_info; do
    node_name=$(echo "$pod_info" | awk '{print $NF}')
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    
    if [[ -n "$node_name" ]]; then
      utilization=$(get_node_gpu_packing_rate "$node_name")
      if [[ "$utilization" =~ ^[0-9.]+$ ]]; then
        printf "  • Pod %-35s on %-20s (GPU utilization: %s%%)\n" "$pod_name" "$node_name" "$utilization"
      else
        echo "  Pod $pod_name scheduled at $node_name (GPU not available)"
      fi
    else
      echo "  • Pod $pod_name not yet assigned to a node"
    fi
  done
}

wait_for_pod_scheduling() {
  local deploy_name=$1
  local expected_replicas=$2
  local timeout=60
  local interval=3
  local elapsed=0
  
  
  while true; do
    echo -n "."
    unscheduled_count=$(kubectl get pod -l app=$deploy_name -o json 2>/dev/null | jq -r '[.items[] | select(.spec.nodeName == null)] | length')
    total_pods=$(kubectl get pod -l app=$deploy_name -o json 2>/dev/null | jq -r '.items | length')
    
    if [[ $total_pods -eq $expected_replicas && $unscheduled_count -eq 0 ]]; then
      return 0
    fi
    
    if ((elapsed % 6 == 0)); then
      for ((i=0; i<elapsed/interval; i++)); do
        echo -n "."
      done
    fi
    
    if [[ $elapsed -ge $timeout ]]; then
      echo -e "\nError: Timeout waiting for pod scheduling at $(timestamp)"
      echo "Unscheduled pods: $unscheduled_count/$expected_replicas"
      kubectl get pod -l app=$deploy_name -o wide
      exit 1
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
}

DEPLOYMENT_NAME="test-gpu-pod"
DEPLOYMENT_FILE="test-gpu-pod-deploy.yaml"

echo "[Step 1] Deploying test deploy (replicas=0) at $(timestamp)"
kubectl apply -f $DEPLOYMENT_FILE > /dev/null
bash check-nodes-gpu-packing-rate.sh
show_highest_gpu_node

echo -e "\n[Step 2] Scaling deployment to 1 replica..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=1 > /dev/null
wait_for_pod_scheduling $DEPLOYMENT_NAME 1
show_pod_scheduling "After scaling to 1 replica"
show_highest_gpu_node

echo -e "\n[Step 3] Scaling deployment to 2 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=2 > /dev/null
wait_for_pod_scheduling $DEPLOYMENT_NAME 2
show_pod_scheduling "After scaling to 2 replicas"
show_highest_gpu_node

echo -e "\n[Step 4] Scaling deployment to 6 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=6 > /dev/null
wait_for_pod_scheduling $DEPLOYMENT_NAME 6
show_pod_scheduling "After scaling to 6 replicas"
show_highest_gpu_node

echo -e "\n[Step 5] Scaling deployment to 7 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=7 > /dev/null
wait_for_pod_scheduling $DEPLOYMENT_NAME 7
show_pod_scheduling "After scaling to 7 replicas"
show_highest_gpu_node

echo -e "\n[Completion] Demo finished at $(timestamp)"
