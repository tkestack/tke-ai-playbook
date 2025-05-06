# TKE AI Playbook

[English](README.md) | [中文](README_zh.md)

## Project Overview
This project provides Kubernetes-based scripts for AI large language model (LLM) operations, including model downloading, inference service deployment, and performance benchmarking, enabling end-to-end AI workflows on Tencent Kubernetes Engine (TKE).

### Prerequisites
1. Kubernetes cluster (recommended v1.28+)
2. Tencent Cloud CFS storage (or compatible storage solution)
3. GPU nodes (3 * H20 nodes used in this project)

### Capabilities

#### Model Download

Use the [Model Download Utility](./helm-charts/model-fetch/README.md) to download models to CFS storage for reuse across inference services.

#### Inference Service Deployment

- [dynamo](./helm-charts/dynamo/README.md): NVIDIA's distributed inference framework (open-sourced at GTC 2025), supporting multiple inference engines including TRT-LLM, vLLM, and SGLang.

#### Performance Benchmarking
- [LLM Benchmark Suite](./helm-charts/benchmark/README.md)


### Examples

#### dynamo

##### Single-Node PD Disaggregation

Prerequisites:
- 1 x 8 GPU Node.

Deploys:
- 1 x VllmWorker (4 GPUs for decode phase)
- 4 x PrefillWorker (1 GPU each for prefill phase)

```bash
bash examples/dynamo/single-node/deploy.sh
```

##### 3 Nodes PD Disaggregation

[TODO]

### Scripts

#### Quick Test for OpenAI-format API Endpoint
1. Script: [test-openai-api](./scripts/test-openai-api.sh)
2. Usage:

```bash
API_ENDPOINT=<your-api-endpoint> bash scripts/test-openai-api.sh

# Test localhost:8080
API_ENDPOINT=http://localhost:8080 bash scripts/test-openai-api.sh
```

#### Generate Model Download Job
1. Script: [tke-llm-downloader](./scripts/tke-llm-downloader.sh)
2. Usage:

```bash
LLM_MODEL=<model-id> PVC_NAME=<your-pvc> bash scripts/tke-llm-downloader.sh
```

