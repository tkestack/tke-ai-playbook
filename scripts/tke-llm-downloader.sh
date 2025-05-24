#!/bin/bash

set -euo pipefail
current_dir=$(cd "$(dirname $0)" && pwd)
source ${current_dir}/utils.sh
Debug "Current directory: ${current_dir}"

NAMESPACE=${NAMESPACE:-""}
LLM_MODEL=${LLM_MODEL:-""}
PVC_NAME=${PVC_NAME:-""}
JOB_COMPLETION_TOTAL=${JOB_COMPLETION_TOTAL:-1}
JOB_PARALLELISM=${JOB_PARALLELISM:-1}
USE_MODELSCOPE=${USE_MODELSCOPE:-"1"}
JOB_NAME=${JOB_NAME:-"tke-llm-downloader"}

if [ -z "${LLM_MODEL}" ]; then
  echo "Please specify a LLM model with LLM_MODEL"
  exit 1
fi

if [ -z "${PVC_NAME}" ]; then
  echo "Please specify a PVC name with PVC_NAME"
  exit 1
fi

Info "Checking requirements..."
MustRequirements kubectl jq awk xargs wc cut grep helm
Success "All required tools are avaliable"

Info "Checking kubernetes cluster connectivity..."
MustConnectToKubernetesCluster
Success "Connected to kubernetes cluster"


KUBE_CMD="kubectl"
if [ ! -z "${NAMESPACE}" ]; then
  KUBE_CMD="kubectl -n ${NAMESPACE}"
  Info "Selected namespace '${NAMESPACE}'"
fi
  
Info "Checking PVC..."
${KUBE_CMD} get pvc ${PVC_NAME} > /dev/null 2>&1 || Fatal "PVC ${PVC_NAME} not found"
Success "PVC '${PVC_NAME}' found"

mkdir -p /tmp/tke-ai-playbook
cat <<EOF > /tmp/tke-ai-playbook/tke-llm-downloader.yaml
apiVersion: batch/v1
kind: Job
metadata:
  generateName: ${JOB_NAME}-
  labels:
    app: ${JOB_NAME}
spec:
  completions: ${JOB_COMPLETION_TOTAL}
  parallelism: ${JOB_PARALLELISM}
  completionMode: Indexed
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - ${JOB_NAME}
      restartPolicy: Never
      containers:
      - name: downloader
        image: tkeai.tencentcloudcr.com/tke-ai-playbook/llm-downloader:v0.0.2
        env:
        - name: JOB_COMPLETION_TOTAL
          value: "${JOB_COMPLETION_TOTAL}"
        - name: USE_MODELSCOPE
          value: "${USE_MODELSCOPE}"
        command: ["bash", "-lc"]
        args: 
        - |
          if [[ "\${USE_MODELSCOPE}" == "1" ]]; then
            uv run python download.py modelscope --model-id=${LLM_MODEL} --local-dir=/data/${LLM_MODEL}
          else
            uv run python download.py huggingface --model-id=${LLM_MODEL} --local-dir=/data/${LLM_MODEL}
          fi
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
EOF
Info "Job to download the LLM model has been generated, see below:"
cat /tmp/tke-ai-playbook/tke-llm-downloader.yaml
Confirm "Do you want to create the job?(y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  ${KUBE_CMD} delete -f /tmp/tke-ai-playbook/tke-llm-downloader.yaml --ignore-not-found
  ${KUBE_CMD} create -f /tmp/tke-ai-playbook/tke-llm-downloader.yaml
  Success "Job created"
fi

indent="          "
Info "Note: following commands can be used to check the logs of the job"
LogCyan "${indent}    ${KUBE_CMD} get pods -l app=${JOB_NAME}"
LogCyan "${indent}    POD_NAME=\$(${KUBE_CMD} get pods -l app=${JOB_NAME} -o jsonpath=\"{.items[0].metadata.name}\")"
LogCyan "${indent}    ${KUBE_CMD} logs -f \${POD_NAME}"
