#/bin/bash

# Current timestamp function
timestamp() {
  date +"%T"
}

show_pod_scheduling() {
  local message=$1
  
  kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " scheduled on " + .spec.nodeName' | \
  while read -r pod_info; do
    node_name=$(echo "$pod_info" | awk '{print $NF}')
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    
    if [[ -n "$node_name" ]]; then
        echo "  Pod $pod_name scheduled at $node_name"
    fi
  done
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

show_lowest_gpu_node() {
  lowest_nodes=()
  lowest_rate=10000
  
  nodes=($(kubectl get nodes -o json | jq -r '.items[].metadata.name'))
  
  for node in "${nodes[@]}"; do
    utilization=$(get_node_gpu_packing_rate "$node")
    
    if [[ "$utilization" =~ ^[0-9.]+$ ]]; then
      if (( $(echo "$utilization > 0" | bc -l) )); then
        if (( $(echo "$utilization < $lowest_rate" | bc -l) )); then
          lowest_rate=$utilization
          lowest_nodes=("$node")
        elif (( $(echo "$utilization == $lowest_rate" | bc -l) )); then
          lowest_nodes+=("$node")
        fi
      fi
    fi
  done
  
  if [[ ${#lowest_nodes[@]} -gt 0 ]]; then
    if [[ ${#lowest_nodes[@]} -eq 1 ]]; then
      echo  "Lowest GPU packing node (with load): ${lowest_nodes[0]} ($lowest_rate%)"
    else
      echo "Lowest GPU packing nodes (with load):"
      for node in "${lowest_nodes[@]}"; do
        echo "  $node ($lowest_rate%)"
      done
    fi
  else
    echo "No nodes with non-zero GPU utilization"
  fi
}

show_pod_terminate() {
  local message=$1
  local terminated_pods=("${!2}")
  
  echo -e "\n$message at $(timestamp)"
  
  for pod_info in "${terminated_pods[@]}"; do
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    echo "   Terminated Pod $pod_name"   
  done
}

wait_for_pod_terminate() {
  local deploy_name=$1
  local expected_replicas=$2
  local timeout=60
  local interval=3
  local elapsed=0
  
  echo -e "\nWaiting for pods to terminate to $expected_replicas replicas..."
  
  while true; do
    current_replicas=$(kubectl get deploy $deploy_name -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    
    if [[ $current_replicas -eq $expected_replicas ]]; then
      return 0
    fi
    
    if ((elapsed % 6 == 0)); then
      dots=$((elapsed/interval))
      progress=$((dots*100/20))
      echo -ne "\rProgress: [$(printf '#%.0s' $(seq 1 $dots))$(printf ' %.0s' $(seq $dots 19))] $progress%"
    fi
    
    if [[ $elapsed -ge $timeout ]]; then
      echo -e "\nError: Timeout waiting for pod termination at $(timestamp)"
      echo "Current replicas: $current_replicas | Expected: $expected_replicas"
      kubectl get pod -l app=$deploy_name -o wide
      exit 1
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
}

get_terminated_pods() {
  local deploy_name=$1
  local previous_pods=("${!2}")
  local current_pods=()
  
  mapfile -t current_pods < <(kubectl get pod -l app=$deploy_name -o json | jq -r '.items[] | .metadata.name + " " + .spec.nodeName')
  
  terminated_pods=()
  for pod_info in "${previous_pods[@]}"; do
    pod_name=$(echo "$pod_info" | awk '{print $1}')
    found=0
    
    for current_info in "${current_pods[@]}"; do
      current_name=$(echo "$current_info" | awk '{print $1}')
      if [[ "$pod_name" == "$current_name" ]]; then
        found=1
        break
      fi
    done
    
    if [[ $found -eq 0 ]]; then
      terminated_pods+=("$pod_info")
    fi
  done
  
  echo "${terminated_pods[@]}"
}


DEPLOYMENT_NAME="test-gpu-pod"
DEPLOYMENT_FILE="test-gpu-pod-deploy.yaml"

echo "[Step 1] Starting with 7 replicas at $(timestamp)"
kubectl scale deploy $DEPLOYMENT_NAME --replicas=7 > /dev/null
bash check-nodes-gpu-packing-rate.sh
mapfile -t current_pods < <(kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " " + .spec.nodeName')
show_pod_scheduling

echo -e "\n[Step 2] Scaling down to 6 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=6 > /dev/null
wait_for_pod_terminate $DEPLOYMENT_NAME 6
terminated_pods=($(get_terminated_pods $DEPLOYMENT_NAME current_pods[@]))
show_pod_scheduling
show_lowest_gpu_node
mapfile -t current_pods < <(kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " " + .spec.nodeName')

echo -e "\n[Step 3] Scaling down to 2 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=2 > /dev/null
wait_for_pod_terminate $DEPLOYMENT_NAME 2
terminated_pods=($(get_terminated_pods $DEPLOYMENT_NAME current_pods[@]))
show_pod_scheduling
show_lowest_gpu_node
mapfile -t current_pods < <(kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " " + .spec.nodeName')

echo -e "\n[Step 4] Scaling down to 1 replica..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=1 > /dev/null
wait_for_pod_terminate $DEPLOYMENT_NAME 1
terminated_pods=($(get_terminated_pods $DEPLOYMENT_NAME current_pods[@]))
show_pod_scheduling
show_lowest_gpu_node
mapfile -t current_pods < <(kubectl get pod -l app=$DEPLOYMENT_NAME -o json | jq -r '.items[] | .metadata.name + " " + .spec.nodeName')

echo -e "\n[Step 5] Scaling down to 0 replicas..."
kubectl scale deploy $DEPLOYMENT_NAME --replicas=0 > /dev/null
wait_for_pod_terminate $DEPLOYMENT_NAME 0
terminated_pods=($(get_terminated_pods $DEPLOYMENT_NAME current_pods[@]))
show_pod_scheduling
show_lowest_gpu_node


echo -e "\n[Completion] Demo finished at $(timestamp)"
