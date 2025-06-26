#!/bin/bash

set -euo pipefail
current_dir=$(cd "$(dirname $0)" && pwd)
script_dir=$(cd "${current_dir}/../../scripts" && pwd)
source ${script_dir}/utils.sh
Debug "Current directory: ${current_dir}"
Debug "Script directory: ${script_dir}"

Info "Checking requirements..."
MustRequirements kubectl jq awk xargs wc cut grep
Success "All required tools are available"

Info "Checking Kubernetes cluster connectivity..."
MustConnectToKubernetesCluster
Success "Connected to Kubernetes cluster"

Info "Which namespace do you want to deploy to?"
PS3="Please select a namespace (enter number): "
select namespace in $(kubectl get namespaces -o name | grep -v system | cut -d / -f 2); do
  break
done
KUBE_CMD="kubectl -n ${namespace}"
Success "Selected namespace '${namespace}'"

Info "Checking Argo Workflow installation..."
if ! kubectl get pods -n argo &> /dev/null; then
  Fatal "Argo Workflow is not installed in the 'argo' namespace. Please install it first."
fi
Success "Argo Workflow is installed"

Info "Checking Kueue installation..."
if ! kubectl get pods -n kueue-system &> /dev/null; then
  Fatal "Kueue is not installed in the 'kueue-system' namespace. Please install it first."
fi
Success "Kueue is installed"

Info "Please provide COS configuration:"
read -p "COS_REGION (e.g., ap-guangzhou): " COS_REGION
read -p "COS_BUCKET: " COS_BUCKET
read -p "COS_SECRET_ID: " COS_SECRET_ID
read -p "COS_SECRET_KEY: " COS_SECRET_KEY

Info "Please provide Kafka configuration:"
read -p "KAFKA_SERVERS: " KAFKA_SERVERS
read -p "KAFKA_SASL_PLAIN_USERNAME: " KAFKA_SASL_PLAIN_USERNAME
read -p "KAFKA_SASL_PLAIN_PASSWORD: " KAFKA_SASL_PLAIN_PASSWORD
read -p "IMAGES_TOPIC: " IMAGES_TOPIC
read -p "BBOXES_TOPIC: " BBOXES_TOPIC
read -p "KAFKA_CONSUMER_GROUP_ID: " KAFKA_CONSUMER_GROUP_ID

Info "Generating workflow template..."
cat <<EOF > /tmp/face-mosaic-processor.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: face-mosaic-processor-job-
spec:
  entrypoint: main
  serviceAccountName: job-creator
  arguments:
    parameters:
    - name: inference_concurrency
      value: 1
    - name: kueue_queue_name
      value: "gpu-pool"
    - name: repeat
      value: "1"
    - name: kafka_servers
      value: "${KAFKA_SERVERS}"
    - name: kafka_sasl_plain_username
      value: "${KAFKA_SASL_PLAIN_USERNAME}"
    - name: kafka_sasl_plain_password
      value: "${KAFKA_SASL_PLAIN_PASSWORD}"
    - name: images_topic
      value: "${IMAGES_TOPIC}"
    - name: bboxes_topic
      value: "${BBOXES_TOPIC}"
    - name: kafka_consumer_group_id
      value: "${KAFKA_CONSUMER_GROUP_ID}"
    - name: cos_region
      value: "${COS_REGION}"
    - name: cos_bucket
      value: "${COS_BUCKET}"
    - name: cos_secret_id
      value: "${COS_SECRET_ID}"
    - name: cos_secret_key
      value: "${COS_SECRET_KEY}"
    - name: draw_type
      value: "mosaic"
    - name: vllm_engine_kwargs
      value: >
        {
          "model": "/models/Qwen/Qwen2.5-VL-7B-Instruct-AWQ",
          "served_model_name": "Qwen/Qwen2.5-VL-7B-Instruct-AWQ",
          "max_model_len": 8192,
          "dtype": "half", 
          "enforce_eager": true
        }
  templates:
  - name: main
    steps:
    - - name: main
        templateRef:
          name: face-mosaic-processor-job
          template: main
EOF

Info "Starting workflow..."
${KUBE_CMD} create -f /tmp/face-mosaic-processor.yaml
Success "Workflow started"

Info "You can monitor the workflow progress in the Argo UI."

