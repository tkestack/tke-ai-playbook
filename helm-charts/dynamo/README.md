# dynamo

[English](README.md) | [中文](README_zh.md)

`dynamo` enables rapid deployment of [dynamo](https://github.com/ai-dynamo/dynamo) with PD disaggregation on Tencent Kubernetes Engine (TKE).

## Architecture Overview

In [dynamo](https://github.com/ai-dynamo/dynamo)'s deployment architecture, a typical inference service comprises:
- **FrontEnd**: OpenAI compatible http server handles incoming requests.
- **Processor**: Request preprocessing before dispatching to workers.
- **Router**: Handles API requests and routes them to appropriate workers based on specified strategy.
- **Worker**: Prefill and decode worker handles actual LLM inference.

`dynamo` implements this architecture using vLLM as the inference engine, organized into two primary deployments:
- **frontend**: Combines FrontEnd, Processor, Router, and ​​VllmWorker​​ for decode-phase operations.
- **prefill-worker (optional)**: Dedicated Worker components for prefill-phase processing.

## Configuration Guide

### Dependencies

| **Dependency** | **Version** | **Enabled by Default** | **Purpose** |
| ---- | ---- | ---- | ---- |
| **etcd** | **11.2.1** | **true** | Distributed key-value store |
| **nats** | **1.3.1** | **true** | High-performance messaging system |

Complete configuration reference:
- etcd: [https://github.com/bitnami/charts/tree/main/bitnami/etcd](https://github.com/bitnami/charts/tree/main/bitnami/etcd)
- nats: [https://github.com/nats-io/k8s/tree/main/helm/charts/nats](https://github.com/nats-io/k8s/tree/main/helm/charts/nats)

### Image Configuration

| Key               | Description                                                     | Default                                             |
|-------------------|-----------------------------------------------------------------|-----------------------------------------------------|
| image.repository  | Docker image repository for the Dynamo component.               | tkeai.tencentcloudcr.com/tke-ai-playbook/dynamo                  |
| image.tag         | Tag version of the Dynamo Docker image.                         | v0.1.1-20250415                                        |
| image.pullPolicy  | Image pull policy for Dynamo containers.                        | IfNotPresent                                        |
| imagePullSecrets  | Kubernetes secrets for authenticating private image registries. | []                                                  |

### Service Configuration

| Key               | Description                                          | Default       |
|-------------------|------------------------------------------------------|---------------|
| service.type      | Network service type for the **frontend** component. | ClusterIP     |
| service.port      | Exposed port number of the **frontend** service.     | 80            |

### Model PVC Configuration

| Key                | Description                                          | Default  |
|--------------------|------------------------------------------------------|----------|
| modelPVC.enable    | Controls whether to mount PVC to the LLM deployment. | true     |
| modelPVC.name      | Name of the Persistent Volume Claim (PVC).           | ai-model |
| modelPVC.mountPath | Mount path for the PVC in the LLM deployment.        | /data    |

### Dynamo Serve Configuration

| Key                      | Description                                                    | Default           |
|--------------------------|----------------------------------------------------------------|-------------------|
| configs                  | Configuration parameters for `single` and `multinode.frontend` | See `values.yaml` |
| prefillConfigs           | Configuration parameters for `multinode.prefill-worker`        | See `values.yaml` |
| graphs."single.py"       | Graph definition file for `single` deployment mode             | See `values.yaml` |
| graphs."frontend.py"     | Graph definition file for `multinode.frontend` component       | See `values.yaml` |

### TKE RDMA Configuration

| Key               | Description                                                                      | Default         |
|-------------------|----------------------------------------------------------------------------------|-----------------|
| rdma.enable       | Controls whether to enable RDMA support.                                         | true            |
| rdma.networkMode  | Network mode annotation to be added to Pod specifications.                       | tke-route-eni   |
| hostNetwork       | Controls whether to use hostNetwork (only effective when `rdma.enable` is true). | true            |

### Single-Node Deployment

| Key                             | Description                                                         | Default                            |
|---------------------------------|---------------------------------------------------------------------|------------------------------------|
| single.enable                   | Controls whether to enable single-node deployment mode.             | true                               |
| single.metrics.enable           | Controls whether to expose metrics in single-node deployments.      | false                              |
| single.metrics.port             | Exposed port for metrics service.                                   | 9091                               |
| single.metrics.image.repository | Docker image repository for metrics component.                      | tkeai.tencentcloudcr.com/tke-ai-playbook/dynamo |
| single.metrics.image.pullPolicy | Image pull policy for metrics containers.                           | IfNotPresent                       |
| single.metrics.image.tag        | Tag version of metrics component Docker image.                      | v0.1.1-20250415               |
| single.metrics.serviceMonitor   | Configuration for Prometheus ServiceMonitor integration.            | See `values.yaml`                  |
| single.labels                   | Extra labels to attach to single-node pods.                         | {}                                 |
| single.annotations              | Extra annotations to apply to single-node pods.                     | {}                                 |
| single.resources                | Resource allocation constraints for single-node deployments.        | See `values.yaml`                  |


### Multinode Deployment

| Key                               | Description                                                | Default                            |
|-----------------------------------|------------------------------------------------------------|------------------------------------|
| multinode.enable                  | Controls whether to enable multi-node deployment mode.     | true                               |
| multinode.replicas                | Number of replicas for `multinode.frontend` component.     | 1                                  |
| multinode.metrics.enable          | Controls whether to expose metrics in multi-node mode.     | false                              |
| multinode.metrics.port            | Exposed port for metrics service.                          | 9091                               |
| multinode.metrics.image.repository| Docker image repository for metrics component.             | tkeai.tencentcloudcr.com/tke-ai-playbook/dynamo |
| multinode.metrics.image.pullPolicy| Image pull policy for metrics containers.                  | IfNotPresent                       |
| multinode.metrics.image.tag       | Tag version of metrics component Docker image.             | v0.1.1-20250415               |
| multinode.metrics.serviceMonitor  | Configuration for Prometheus ServiceMonitor integration.   | See `values.yaml`                  |
| multinode.labels                  | Extra labels to attach to multi-node pods.                 | {}                                 |
| multinode.annotations             | Extra annotations to apply to multi-node pods.             | {}                                 |
| multinode.resources               | Resource allocation for `multinode.frontend` containers.   | See `values.yaml`                  |
| multinode.prefill.replicas        | Number of `multinode.prefill-worker` replicas.             | 1                                  |
| multinode.prefill.resources       | Resource allocation for `multinode.prefill-worker` pods.   | See `values.yaml`                  |

## Examples

### Single-Node PD Disaggregation

Prerequisites:
- 1 x H20*8 GPU Node.
- Model neuralmagic/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic downloaded to /data path of PVC 'ai-model'.

Deploys:
- 1 x VllmWorker (4 GPUs for decode phase)
- 4 x PrefillWorker (1 GPU each for prefill phase)

```bash
# With RDMA
helm install deepseek-r1-llama-70b . -f values.yaml

# Without RDMA 
helm install deepseek-r1-llama-70b . -f values.yaml --set rdma.enable=false
```

### Multinode PD Disaggregation

Prerequisites:
- 3 x H20*8 GPU Node.
- Model neuralmagic/DeepSeek-R1-Distill-Llama-70B-FP8-dynamic downloaded to /data path of PVC 'ai-model'.

Deploys:
- **Node1**: 1 x VllmWorker (4 GPUs for decode phase) + 4 x PrefillWorker (1 GPU each for prefill phase)
- **Node2**: 8 x PrefillWorker (1 GPU each for prefill phase)
- **Node3**: 8 x PrefillWorker (1 GPU each for prefill phase)

Total resources:
- 24 GPUs allocated (4 for decoding, 20 for prefilling)

```bash
# With RDMA
helm install deepseek-r1-llama-70b . -f multi-values.yaml

# Without RDMA
helm install deepseek-r1-llama-70b . -f multi-values.yaml --set rdma.enable=false
```
