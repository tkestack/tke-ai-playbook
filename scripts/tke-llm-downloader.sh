#!/bin/bash

set -euo pipefail
current_dir=$(cd "$(dirname $0)" && pwd)
source ${current_dir}/utils.sh

# Function to print help message
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo "Examples:"
  echo "  Download 'deepseek-ai/DeepSeek-R1' model to PVC 'ai-model' with 6 concurrency"
  echo "    $0 --pvc ai-model --completions 6 --parallelism 6 --model deepseek-ai/DeepSeek-R1"
  echo "  Download 'Qwen/Qwen3-32B' model to PVC 'ai-model' with 3 concurrency"
  echo "    $0 --pvc ai-model --completions 3 --parallelism 3 --model Qwen/Qwen3-32B"
  echo ""
  echo "Options:"
  echo "  --namespace <namespace>        Kubernetes namespace (default: "")"
  echo "  --model <model_id>             LLM model to download (required)"
  echo "  --pvc <pvc_name>               PVC name for storage (required)"
  echo "  --completions <int>            Job completions (default: 1)"
  echo "  --parallelism <int>            Job parallelism (default: 1)"
  echo "  --use-modelscope <0|1>         Use ModelScope for download (default: 1)"
  echo "  --job-name <name>              Job name prefix (default: tke-llm-downloader)"
  echo "  --node-selector <key=value>    Node selector for pods (default: "")"
  echo "  -h, --help                     Show this help message and exit"
  exit 0
}

search_model_on_modelscope() {
  curl -s 'https://modelscope.cn/api/v1/dolphin/models' \
    -X 'PUT' \
    -H 'Content-Type: application/json' \
    --data-raw '{"PageSize":10,"PageNumber":1,"SortBy":"Default","Target":"","SingleCriterion":[],"Name":"'$1'","Criterion":[]}' | \
  jq -r '.Data.Model.Models[] | .Path + "/" + .Name'
}

# Function to parse command line arguments
get_options() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --namespace)
        NAMESPACE="$2"
        shift 2
        ;;
      --model)
        LLM_MODEL="$2"
        shift 2
        ;;
      --pvc)
        PVC_NAME="$2"
        shift 2
        ;;
      --completions)
        JOB_COMPLETION_TOTAL="$2"
        shift 2
        ;;
      --parallelism)
        JOB_PARALLELISM="$2"
        shift 2
        ;;
      --use-modelscope)
        USE_MODELSCOPE="$2"
        shift 2
        ;;
      --job-name)
        JOB_NAME="$2"
        shift 2
        ;;
      --node-selector)
        NODE_SELECTOR="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 1
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done
}

# Initialize default values
NAMESPACE=${NAMESPACE:-""}
LLM_MODEL=${LLM_MODEL:-""}
PVC_NAME=${PVC_NAME:-""}
JOB_COMPLETION_TOTAL=${JOB_COMPLETION_TOTAL:-1}
JOB_PARALLELISM=${JOB_PARALLELISM:-1}
USE_MODELSCOPE=${USE_MODELSCOPE:-"1"}
JOB_NAME=${JOB_NAME:-"tke-llm-downloader"}
NODE_SELECTOR=${NODE_SELECTOR:-""}

# Parse command line arguments
get_options "$@"

if [ -z "${LLM_MODEL}" ]; then
  if [ "${USE_MODELSCOPE}" == "1" ]; then
    Confirm "Do you want to search model on ModelScope?(y/n): "
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        Confirm "Please type the search keyword: "
        if [[ -z "$REPLY" ]]; then
          Fatal "Please type the search keyword"
        fi
        PS3="Please select a model(enter number): "
        select LLM_MODEL in $(search_model_on_modelscope "${REPLY}"); do
          break
        done
    else
      Fatal "Please specify a LLM model with --model"
    fi
  else
    Fatal "Please specify a LLM model with --model"
  fi
fi

if [ -z "${PVC_NAME}" ]; then
  Fatal "Please specify a PVC name with --pvc"
fi

Info "Checking requirements..."
MustRequirements kubectl jq awk xargs wc cut grep helm
Success "All required tools are available"

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

TEMP_DIR=$(mktemp -d)
if [ ! -z "${NODE_SELECTOR}" ]; then
# split NODE_SELECTOR into key-value pairs
IFS=',' read -ra NODE_SELECTOR_PAIRS <<< "${NODE_SELECTOR}"

# generate nodeSelector section
NODE_SELECTOR_SECTION=""

for PAIR in "${NODE_SELECTOR_PAIRS[@]}"; do
  IFS='=' read -ra KEY_VALUE <<< "${PAIR}"
  NODE_SELECTOR_SECTION="${NODE_SELECTOR_SECTION}
              - key: ${KEY_VALUE[0]}
                operator: In
                values:
                - ${KEY_VALUE[1]}"
done

  # generate job yaml
cat <<EOF > ${TEMP_DIR}/tke-llm-downloader.yaml
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
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:${NODE_SELECTOR_SECTION}
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
        image: tkeai.tencentcloudcr.com/tke-ai-playbook/llm-downloader:latest
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
else
cat <<EOF > ${TEMP_DIR}/tke-llm-downloader.yaml
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
        image: tkeai.tencentcloudcr.com/tke-ai-playbook/llm-downloader:latest
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
fi

Info "Job to download the LLM model has been generated, see below:"
cat ${TEMP_DIR}/tke-llm-downloader.yaml
Confirm "Do you want to create the job?(y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  ${KUBE_CMD} create -f ${TEMP_DIR}/tke-llm-downloader.yaml
  Success "Job created"
  indent="          "
  Info "Note: following commands can be used to check the logs of the job"
  LogCyan "${indent}    ${KUBE_CMD} get pods -l app=${JOB_NAME}"
  LogCyan "${indent}    POD_NAME=\$(${KUBE_CMD} get pods -l app=${JOB_NAME} -o jsonpath=\"{.items[0].metadata.name}\")"
  LogCyan "${indent}    ${KUBE_CMD} logs -f \${POD_NAME}"
else
  Info "Job not created"
  exit 0
fi

