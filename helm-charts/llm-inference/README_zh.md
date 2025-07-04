# LLM 推理部署

[English](README.md) | [中文](README_zh.md)

`llm-inference` 用于部署大语言模型（LLM）推理服务，支持 vLLM 和 Sglang 等主流推理引擎。

## 配置说明

以下是主要可配置的参数及默认值：

### 基础配置

| 参数 | 类型 | 描述 | 默认值 | 是否必填 |
|------|------|------|--------|----------|
| `image` | string | 容器镜像地址 | `tkeai.tencentcloudcr.com/tke-ai-playbook/vllm-openai:v0.8.5.r1-qwen-1.5b` | 是 |
| `imagePullPolicy` | string | 镜像拉取策略 | `IfNotPresent` | 否 |
| `replicas` | int | 容器副本数 | `1` | 否 |
| `command` | list | 容器启动命令 |  | 是 |
| `resources` | map | 容器资源 | | 否 |
| `affinity` | map |  亲和性调度 | | 否 |
| `env` | map | 环境变量 | | 否 |
| `volumeMounts` | map |  存储挂载 | | 否 |
| `volumes` | map |  存储 | | 否 |
| `readinessProbe` | map |  存活探针 | | 否 |
| `lifecycle` | map | 生命周期 | | 否 |

### 服务配置

| 参数 | 类型 | 描述 | 默认值 | 是否必填 |
|------|------|------|--------|----------|
| `serverPort` | int | 容器内部服务端口 | `30000` | 是 |
| `exposePort` | int | 对外暴露端口 | `80` | 否 |

### 弹性伸缩配置

| 参数 | 类型 | 描述 | 默认值 | 是否必填 |
|------|------|------|--------|----------|
| `autoscaling.enabled` | bool | 是否开启弹性伸缩 | `false` | 否 |
| `autoscaling.replicas.minimum` | int | 最小副本数 | `1` | 否 |
| `autoscaling.replicas.maximum` | int | 最大副本数 | `2` | 否 |
| `autoscaling.metric.name` | int | 指标名 | `vllm:gpu_cache_usage_perc` | 否 |
| `autoscaling.metric.value` | int | 指标名 | `0.3` | 否 |

## 使用说明

1. 模型下载（可选）

参考 [model-fetch](../model-fetch/README.md) 部署模型下载服务。

首先需要在腾讯云控制台上创建 storage class，假设创建的 storage class 名为 `cfs-ai`。

执行如下命令可以创建绑定到 `cfs-ai` 的名为 `ai-model` 的PVC，并创建一个 job 用来拉取模型 `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B`：

```bash
helm install model-fetch . -f values.yaml \
  --set modelName=deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
  --set pvcName=ai-model \
  --set storageClassName=cfs-ai
```

2. 推理部署

执行如下命令可以部署推理服务：

```shell
helm install llm-inference ./llm-inference
```

3. CFS 挂载（可选）

如果需要挂载CFS（Cloud File Storage）到容器中，可以在values.yaml中配置volumeMounts和volumes：

```yaml
volumeMounts:
  - name: cfs-volume
    mountPath: /data
volumes:
  - name: cfs-volume
    persistentVolumeClaim:
      claimName: ai-model
```

4. 观察服务的运行情况

```shell
kubectl get pod -l app=llm-inference
```

## 服务访问

将服务转发到本地，将占用本地的8080端口，参考[port-forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/?spm=5176.28197681.0.0.6e535ff60pHceq)。

```bash
export POD_NAME=$(kubectl get pods --namespace default -l "app=llm-inference" -o jsonpath="{.items[0].metadata.name}")
export CONTAINER_PORT=$(kubectl get pod --namespace default $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
kubectl --namespace default port-forward $POD_NAME 8080:$CONTAINER_PORT
```
命令执行成功后，输出内容如下。
```text
Forwarding from 127.0.0.1:8080 -> 80
Forwarding from [::1]:8080 -> 80
```

在本地使用 curl 命令进行测试：

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