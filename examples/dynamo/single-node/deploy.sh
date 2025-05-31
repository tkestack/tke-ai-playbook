#!/bin/bash

set -euo pipefail
current_dir=$(cd "$(dirname $0)" && pwd)
script_dir=$(cd "${current_dir}/../../../scripts" && pwd)
helm_dir=$(cd "${current_dir}/../../../helm-charts" && pwd)
source ${script_dir}/utils.sh
Debug "Current directory: ${current_dir}"
Debug "Script directory: ${script_dir}"
Debug "Helm charts directory: ${helm_dir}"

Info "Checking requirements..."
MustRequirements kubectl jq awk xargs wc cut grep helm
Success "All required tools are avaliable"

Info "Checking kubernetes cluster connectivity..."
MustConnectToKubernetesCluster
Success "Connected to kubernetes cluster"

Info "Which namespace do you want to deploy?"
PS3="Please select a namespace(enter number): "
select namespace in $(kubectl get namespaces -o name | grep -v kube-system | cut -d / -f 2); do
  break
done
KUBE_CMD="kubectl -n ${namespace}"
HELM_CMD="helm -n ${namespace}"
Success "Selected namespace '${namespace}'"
  
Info "Checking PVC..."
READ_WRITE_MANY_PVC=$(${KUBE_CMD} get pvc -o jsonpath='{range .items[?(@.spec.accessModes[*] == "ReadWriteMany")]}{.metadata.name}{" "}{end}')
if [[ -z "${READ_WRITE_MANY_PVC}" ]]; then
  Fatal "No PVC with ReadWriteMany access mode found, please create one first"
fi
READ_WRITE_MANY_PVC_COUNT=$(echo ${READ_WRITE_MANY_PVC} | wc -w)
if [[ ${READ_WRITE_MANY_PVC_COUNT} -gt 1 ]]; then
  Info "Multiple PVCs with ReadWriteMany access mode detected. Which one would you like to use for storing the LLM model?"
  PS3="Please select a PVC(enter number): "
  select pvc in ${READ_WRITE_MANY_PVC}; do
    break
  done
  Success "Selected pvc '${pvc}'"
elif [[ ${READ_WRITE_MANY_PVC_COUNT} -eq 1 ]]; then
  pvc=$(echo ${READ_WRITE_MANY_PVC} | xargs)
  Info "Only one PVC with ReadWriteMany access mode detected"
  Confirm "Do you want to use the '${pvc}' PVC to store the LLM model? (y/n): "
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    Success "Selected pvc '${pvc}'"
  else
    Fatal "Please create a PVC with ReadWriteMany access mode first"
  fi
else
  Fatal "Unexpected error while detecting PVCs, got '${READ_WRITE_MANY_PVC_COUNT}' pvc(s) with ReadWriteMany access mode"
fi

Info "Which LLM model do you want to deploy?"
PS3="Please select a LLM model(enter number): "
select model in \
  "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B" \
  "deepseek-ai/DeepSeek-R1-Distill-Qwen-32B" \
  "deepseek-ai/DeepSeek-R1-Distill-Llama-70B" \
  "neuralmagic/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic" \
  "custom"; do
  break
done
if [[ "${model}" == "custom" ]]; then
  Confirm "Please enter the LLM model name: "
  model=$REPLY
fi
Success "Selected LLM model '${model}'"

Confirm "Do you want to create the job to download the LLM model? (y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  Info "Generating a job to download the LLM model..."
  Info "Would you like to use huggingface or modelscope to download the LLM model?"
  PS3="Please select a tool(enter number): "
  select download_llm_tool in huggingface modelscope; do
    break
  done
  if [[ "${download_llm_tool}" == "huggingface" ]]; then
    USE_MODELSCOPE="0"
  else
    USE_MODELSCOPE="1"
  fi
  Success "Selected tool '${download_llm_tool}'"
  mkdir -p /tmp/tke-ai-playbook
  cat <<EOF > /tmp/tke-ai-playbook/tke-llm-downloader.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: tke-llm-downloader
  namespace: ${namespace}
  labels:
    app: tke-llm-downloader
spec:
  backoffLimit: 0
  template:
    metadata:
      name: tke-llm-downloader
      labels:
        app: tke-llm-downloader
    spec:
      containers:
      - name: downloader
        image: tkeai.tencentcloudcr.com/tke-ai-playbook/llm-downloader:v0.0.1
        env:
        - name: LLM_MODEL
          value: ${model}
        - name: USE_MODELSCOPE
          value: "${USE_MODELSCOPE}"
        command:
        - bash
        - -c
        - |
          set -ex
          if [[ "\${USE_MODELSCOPE}" == "1" ]]; then
            exec modelscope download --local_dir=/data/\$LLM_MODEL --model="\$LLM_MODEL"
          else
            exec huggingface-cli download --local-dir=/data/\$LLM_MODEL \$LLM_MODEL
          fi
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${pvc}
      restartPolicy: Never
EOF
  Info "Job to download the LLM model has been generated."
  cat /tmp/tke-ai-playbook/tke-llm-downloader.yaml
  Confirm "Do you want to create the job to download the LLM model? (y/n): "
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    Info "Creating the job to download the LLM model..."
    ${KUBE_CMD} delete -f /tmp/tke-ai-playbook/tke-llm-downloader.yaml --ignore-not-found
    ${KUBE_CMD} create -f /tmp/tke-ai-playbook/tke-llm-downloader.yaml
    Info "Waiting for the job to complete...(this may take a while)"
    ok="false"
    for i in {1..100}; do
      sleep 1
      ${KUBE_CMD} get pods -l app=tke-llm-downloader | grep -E "Running|Completed|Error" &> /dev/null && \
        ${KUBE_CMD} logs -f job/tke-llm-downloader && ok="true" && break
    done
    if [[ "${ok}" == "false" ]]; then
      Fatal "The job took a long time to start, please check the job."
    fi
    Info "Checking the job status..." && sleep 5
    LLM_DOWNLOADER_STATUS=$(${KUBE_CMD} get job tke-llm-downloader -o jsonpath='{.status.conditions[0].type}')
    if [[ "${LLM_DOWNLOADER_STATUS}" == "Complete" ]]; then
      Success "Job status is '${LLM_DOWNLOADER_STATUS}', the LLM model has been downloaded."
    else
      Fatal "Job status is '${LLM_DOWNLOADER_STATUS}', please check the job."
    fi
  else
    Info "exit" && exit 1
  fi
else
  Warn "Note: Ensure model files exist at '/data/${model}' in your PVC '${pvc}'"
fi

Info "Generating the values.yaml file for the 'dynamo' chart..."
Confirm "Please enter the release name for the 'dynamo' chart: "
HELM_RELEASE_NAME="${REPLY}"
Confirm "Do you want to enable RDMA? (y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  RDMA="true"
  Info "Checking cluster network mode..."
  CLUSTER_NETWORK_MODE=$(kubectl -nkube-system get cm tke-cni-agent-conf -oyaml | grep defaultDelegates | awk '{print $2}' | tr -d "\",")
  if [[ "${CLUSTER_NETWORK_MODE}" == "tke-route-eni" ]]; then
    Info "The cluster network mode is 'tke-route-eni', RDMA is enabled"
  elif [[ "${CLUSTER_NETWORK_MODE}" == "tke-bridge" ]]; then
    Info "The cluster network mode is 'tke-bridge', RDMA is enabled"
  else
    Fatal "The cluster network mode is '${CLUSTER_NETWORK_MODE}', RDMA is not supported"
  fi
  Confirm "Do you want to use hostNetwork? (y/n): "
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    USE_HOSTNETWORK="true"
    Info "Using hostNetwork"
  else
    USE_HOSTNETWORK="false"
  fi
else
  RDMA="false"
  Info "RDMA is disabled"
fi
mkdir -p /tmp/tke-ai-playbook/dynamo
cat <<EOF > /tmp/tke-ai-playbook/dynamo/values.yaml
modelPVC:
  enable: ${RDMA}
  name: ai-model
  mountPath: /data

configs: |
  Common:
    model: /data/${model}
    block-size: 64
    max-model-len: 16384
    router: kv
    kv-transfer-config: '{"kv_connector":"DynamoNixlConnector"}'
    max-num-batched-tokens: 16384

  Frontend:
    served_model_name: ${model}
    endpoint: dynamo.Processor.chat/completions
    port: 8000

  Processor:
    common-configs: [model, block-size, max-model-len, router]

  Router:
    min-workers: 1
    model: ${model}

  VllmWorker:
    enable-prefix-caching: true
    remote-prefill: true
    conditional-disagg: true
    max-local-prefill-length: 10
    max-prefill-queue-size: 2
    tensor-parallel-size: 4
    ServiceArgs:
      workers: 1
      resources:
        gpu: 4
    common-configs: [model, block-size, max-model-len, router, kv-transfer-config, max-num-batched-tokens]

  PrefillWorker:
    tensor-parallel-size: 1
    ServiceArgs:
      workers: 4
      resources:
        gpu: 1
    common-configs: [model, block-size, max-model-len, kv-transfer-config, max-num-batched-tokens]

graphs:
  single.py: |
    from components.frontend import Frontend
    from components.kv_router import Router
    from components.prefill_worker import PrefillWorker
    from components.processor import Processor
    from components.worker import VllmWorker
    Frontend.link(Processor).link(Router).link(VllmWorker).link(PrefillWorker)

rdma:
  enable: ${RDMA}
  networkMode: "${CLUSTER_NETWORK_MODE}"
  hostNetwork: ${USE_HOSTNETWORK}

single:
  enable: true
  metrics:
    enable: false
    serviceMonitor:
      enable: false
  labels: {}
  annotations: {}
  resources:
    requests:
      nvidia.com/gpu: 8
    limits:
      nvidia.com/gpu: 8

multinode:
  enable: false
EOF
Confirm "Do you want to see the values.yaml? (y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  cat /tmp/tke-ai-playbook/dynamo/values.yaml
fi
Confirm "Dynamo on TKE(Single Node): Are you sure you want to install this chart? (y/n): "
if [[ $REPLY =~ ^[Yy]$ ]]; then
  Info "Dynamo on TKE(Single Node): Installing..."
  ${HELM_CMD} upgrade --install ${HELM_RELEASE_NAME} ${helm_dir}/dynamo -f /tmp/tke-ai-playbook/dynamo/values.yaml
else
  Info "exit" && exit 1
fi

indent="          "
Success "Dynamo on TKE(Single Node): Installation completed"
Info "Note: Please wait a few minutes for the inference service to be ready"
Info "Note: You can check the status of the inference service by running the following command:"
LogCyan "${indent}    ${KUBE_CMD} get pods -l app.kubernetes.io/instance=${HELM_RELEASE_NAME}"
LogCyan "${indent}    POD_NAME=\$(${KUBE_CMD} get pods -l app.kubernetes.io/instance=${HELM_RELEASE_NAME},app.kubernetes.io/dynamo-component=single -o jsonpath=\"{.items[0].metadata.name}\")"
LogCyan "${indent}    ${KUBE_CMD} logs -f \${POD_NAME}"
Info "Note: While the inference service is ready, you can access the inference service by running the following command:"
LogCyan "${indent}    ${KUBE_CMD} exec \${POD_NAME} -- curl -X POST \"http://localhost:8000/v1/chat/completions\" \\
${indent}        -H \"Content-Type: application/json\" \\
${indent}        -d '{
${indent}            \"model\": \"${model}\",
${indent}            \"messages\": [
${indent}                {\"role\": \"system\", \"content\": \"you are a AI programming assistant\"},
${indent}                {\"role\": \"user\", \"content\": \"use python to implement quick sort algorithm\"}
${indent}            ],
${indent}            \"temperature\": 0.3,
${indent}            \"max_tokens\": 512,
${indent}            \"top_p\": 0.9
${indent}        }'
"