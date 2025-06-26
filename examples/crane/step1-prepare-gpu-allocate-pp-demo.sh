#!/bin/bash
set -e
TARGET_IMAGE="ccr.ccs.tencentyun.com/tkeimages/crane-scheduler-controller:v1.6.4-rc1"
PP_NAME="qwen-hpa-demo-compact-scheduling"

KWOK_DEPLOYMENT="deployment/kwok-controller"
TARGET_KWOK_IMAGE="ccr.ccs.tencentyun.com/shaoxu/kwok:0.6.0"

wait_for_image_update() {
    local resource_type="$1"
    local namespace="$2"
    local resource_name="$3"
    local container_name="$4"
    local target_image="$5"
    local max_attempts=20
    local attempts=0
    
    echo -n "Waiting for $resource_name to update to image: $target_image..."
    while true; do
        current_image=$(kubectl -n $namespace get $resource_type $resource_name \
            -ojsonpath="{.spec.template.spec.containers[?(@.name=='$container_name')].image}" 2>/dev/null)
        
        if [[ "$current_image" == "$target_image" ]]; then
            echo "[OK]"
            break
        fi
        
        attempts=$((attempts + 1))
        if [[ $attempts -ge $max_attempts ]]; then
            echo "ERROR: Timeout waiting for $resource_name to update"
            echo "Current image: $current_image"
            echo "Target image: $target_image"
            exit 1
        fi
        
        echo -n "."
        sleep 3
    done
}

# Step1: Install crane-scheduler if not already exists
cd install && bash install-cranescheduler.sh

cd ../

# Step2: Deploy kwok-controller if not already exists
if kubectl get -n kube-system $KWOK_DEPLOYMENT > /dev/null 2>&1; then
    READY_REPLICAS=$(kubectl get -n kube-system $KWOK_DEPLOYMENT -ojsonpath='{.status.readyReplicas}' || echo "0")
    CURRENT_IMAGE=$(kubectl get -n kube-system $KWOK_DEPLOYMENT -ojsonpath='{.spec.template.spec.containers[?(@.name=="kwok-controller")].image}')
    
    if [[ "$READY_REPLICAS" -ge 1 && "$CURRENT_IMAGE" == "$TARGET_KWOK_IMAGE" ]]; then
        echo "kwok-controller is already ready (readyReplicas=$READY_REPLICAS) with target image"
    else
        echo "kwok-controller exists but not ready (readyReplicas=$READY_REPLICAS) or has incorrect image, redeploying..."
        kubectl delete -n kube-system $KWOK_DEPLOYMENT
    fi
fi


# Install or reinstall if needed
if ! kubectl get -n kube-system $KWOK_DEPLOYMENT > /dev/null 2>&1; then
    echo "Installing kwok-controller..."
    
    kubectl apply -f "https://github.com/kubernetes-sigs/kwok/releases/download/v0.6.0/kwok.yaml" > /dev/null
    kubectl apply -f "https://github.com/kubernetes-sigs/kwok/releases/download/v0.6.0/stage-fast.yaml" > /dev/null
    
    # Update image to our target version
    kubectl -n kube-system set image deployment/kwok-controller kwok-controller=$TARGET_KWOK_IMAGE > /dev/null
    echo "kwok-controller installed"
else
    echo "kwok-controller already exists and ready, skipping installation"
fi

# Step3: Deploy 2 new kwok GPU nodes
# Initialize node number
number=1

# Find next available node numbers
while true; do
    if ! kubectl get node "gpu-node-$number" > /dev/null 2>&1; then
        node1="gpu-node-$number"
        ((number++))
        node2="gpu-node-$number"
        break
    fi
    ((number++))
done

echo "Deploying GPU nodes: $node1 and $node2"

# Create first node
kubectl apply -f - <<EOF
apiVersion: v1
kind: Node
metadata:
  annotations:
    node.alpha.kubernetes.io/ttl: "0"
    kwok.x-k8s.io/node: fake
  labels:
    beta.kubernetes.io/arch: amd64
    beta.kubernetes.io/instance-type: kwok
    beta.kubernetes.io/os: linux
    keyresource: kwok-gpu
    cloud.tencent.com/provider: tencentcloud
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: $node1
    kubernetes.io/os: linux
    type: kwok
  name: $node1
spec:
  taints:
  - effect: NoSchedule
    key: kwok.x-k8s.io/node
    value: fake
status:
  allocatable:
    cpu: 32
    memory: 256Gi
    nvidia.com/gpu: "8"
    pods: 110
  capacity:
    cpu: 32
    memory: 256Gi
    nvidia.com/gpu: "8"
    pods: 110
  nodeInfo:
    architecture: amd64
    bootID: ""
    containerRuntimeVersion: kwok-v0.6.0
    kernelVersion: kwok-v0.6.0
    kubeProxyVersion: fake
    kubeletVersion: fake
    machineID: ""
    operatingSystem: linux
    osImage: ""
    systemUUID: ""
  phase: Running
EOF

# Create second node
kubectl apply -f - <<EOF
apiVersion: v1
kind: Node
metadata:
  annotations:
    node.alpha.kubernetes.io/ttl: "0"
    kwok.x-k8s.io/node: fake
  labels:
    beta.kubernetes.io/arch: amd64
    beta.kubernetes.io/instance-type: kwok
    beta.kubernetes.io/os: linux
    keyresource: kwok-gpu
    cloud.tencent.com/provider: tencentcloud
    kubernetes.io/arch: amd64
    kubernetes.io/hostname: $node2
    kubernetes.io/os: linux
    type: kwok
  name: $node2
spec:
  taints:
  - effect: NoSchedule
    key: kwok.x-k8s.io/node
    value: fake
status:
  allocatable:
    cpu: 32
    memory: 256Gi
    nvidia.com/gpu: "8"
    pods: 110
  capacity:
    cpu: 32
    memory: 256Gi
    nvidia.com/gpu: "8"
    pods: 110
  nodeInfo:
    architecture: amd64
    bootID: ""
    containerRuntimeVersion: kwok-v0.6.0
    kernelVersion: kwok-v0.6.0
    kubeProxyVersion: fake
    kubeletVersion: fake
    machineID: ""
    operatingSystem: linux
    osImage: ""
    systemUUID: ""
  phase: Running
EOF

# Step4: Update crane-scheduler-controller image
CURRENT_IMAGE=$(kubectl -n kube-system get deploy crane-scheduler-controller -ojsonpath='{.spec.template.spec.containers[?(@.name=="controller")].image}')
kubectl -n kube-system label service crane-scheduler-controller app=crane-scheduler-controller
kubectl -n kube-system apply -f cranecontroller-svcmonitor.yaml
if [[ "$CURRENT_IMAGE" == "$TARGET_IMAGE" ]]; then
    echo "crane-scheduler-controller already using target image"
    echo "Skipping image update"
else
    echo "Current crane-scheduler-controller image: $CURRENT_IMAGE"
    echo "Updating to target image: $TARGET_IMAGE"
    kubectl -n kube-system set image deploy/crane-scheduler-controller controller="$TARGET_IMAGE" > /dev/null
fi


# Step4: Apply placement policy
if kubectl get pp "$PP_NAME" >/dev/null 2>&1; then
    echo "PlacementPolicy '$PP_NAME' already exists, skipping creation"
else
    echo "Creating PlacementPolicy '$PP_NAME'..."
    kubectl apply -f placementpolicy-gpu-most.yaml > /dev/null
fi

# Step5: Wait for all components to be ready
echo "Waiting for all components to become ready..."

wait_for_resource() {
    local cmd="$1"
    local check="$2"
    local name="$3"
    
    echo -n "Waiting for $name to be ready..."
    while ! $cmd | grep -q "$check"; do
        echo -n "."
        sleep 3
    done
    echo "[OK]"
}

# Verify kwok-controller
wait_for_resource "kubectl -n kube-system get deployment kwok-controller -ojsonpath='{.status.readyReplicas}'" "1" "kwok-controller"

# Verify kwok nodes
wait_for_resource "kubectl get nodes --no-headers" "gpu-node" "kwok GPU nodes"

# Verify placement policy
wait_for_resource "kubectl get pp" "qwen-hpa-demo-compact-scheduling" "PlacementPolicy"

# Verify crane-scheduler-controller
wait_for_resource "kubectl -n kube-system get deployment crane-scheduler-controller -ojsonpath='{.status.readyReplicas}'" "2" "crane-scheduler-controller"

# Wait for crane-scheduler-controller image update
wait_for_image_update "deployment" "kube-system" "crane-scheduler-controller" "controller" "$TARGET_IMAGE"


# Step6: Check initial GPU packing rate
echo "Checking initial GPU packing rate..."
bash check-nodes-gpu-packing-rate.sh

echo "Environment preparation completed successfully!"
