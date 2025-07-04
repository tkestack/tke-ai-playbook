# LLM Inference Deployment

[English](README.md) | [中文](README_zh.md)

`llm-inference` is designed to deploy inference services for large language models (LLMs), supporting mainstream inference engines like vLLM and Sglang.

## Configuration

Below are the configurable parameters with their default values:

### Basic Configuration

| Parameter | Type | Description | Default | Required |
|-----------|------|-------------|---------|----------|
| `image` | string | Container image address | `tkeai.tencentcloudcr.com/tke-ai-playbook/vllm-openai:v0.8.5.r1-qwen-1.5b` | Yes |
| `imagePullPolicy` | string | Image pull policy | `IfNotPresent` | No |
| `replicas` | int | Number of container replicas | `1` | No |
| `command` | list | Container startup command |  | Yes |
| `resources` | map | Container resources | | No |
| `affinity` | map | Affinity scheduling | | No |
| `env` | map | Environment variables | | No |
| `volumeMounts` | map | Storage mounts | | No |
| `volumes` | map | Storage configuration | | No |
| `readinessProbe` | map | Readiness probe | | No |
| `lifecycle` | map | Lifecycle hooks | | No |

### Service Configuration

| Parameter | Type | Description | Default | Required |
|-----------|------|-------------|---------|----------|
| `serverPort` | int | Internal service port | `30000` | Yes |
| `exposePort` | int | Externally exposed port | `80` | No |

### Auto-scaling Configuration

| Parameter | Type | Description | Default | Required |
|-----------|------|-------------|---------|----------|
| `autoscaling.enabled` | bool | Whether to enable auto-scaling | `false` | No |
| `autoscaling.replicas.minimum` | int | Minimum number of replicas | `1` | No |
| `autoscaling.replicas.maximum` | int | Maximum number of replicas | `2` | No |
| `autoscaling.metric.name` | string | Metric name | `vllm:gpu_cache_usage_perc` | No |
| `autoscaling.metric.value` | float | Metric threshold | `0.3` | No |

## Usage Instructions

1. Model Download (Optional)

Refer to [model-fetch](../model-fetch/README.md) to deploy the model download service.

First, create a StorageClass named `cfs-ai` in Tencent Cloud Console.

Execute the following command to create a PVC named `ai-model` bound to `cfs-ai`, and create a Job to download the model `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B`:

```bash
helm install model-fetch . -f values.yaml \
  --set modelName=deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
  --set pvcName=ai-model \
  --set storageClassName=cfs-ai
```

2. Inference Deployment

Execute the following command to deploy the inference service:

```shell
helm install llm-inference ./llm-inference
```

3. CFS Mount (Optional)

If you need to mount CFS (Cloud File Storage) to the container, configure volumeMounts and volumes in values.yaml:

```yaml
volumeMounts:
  - name: cfs-volume
    mountPath: /data
volumes:
  - name: cfs-volume
    persistentVolumeClaim:
      claimName: ai-model
```

4. Observe the service running status

```shell
kubectl get pod -l app=llm-inference
```

## Service Access

Forward the service to the local, which will occupy the local port 8080, refer to [port-forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/?spm=5176.28197681.0.0.6e535ff60pHceq).

```shell
export POD_NAME=$(kubectl get pods --namespace default -l "app=llm-inference" -o jsonpath="{.items[0].metadata.name}")
export CONTAINER_PORT=$(kubectl get pod --namespace default $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
kubectl --namespace default port-forward $POD_NAME 8080:$CONTAINER_PORT
```

Upon successful execution, you'll see output similar to:

```text
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
```

Test the service locally using curl:

```shell
curl -v -XPOST http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B",
    "max_tokens": 20,
    "messages": [
      {
        "role": "user",
        "content": "Who are you?"
      }
    ]
  }'
```