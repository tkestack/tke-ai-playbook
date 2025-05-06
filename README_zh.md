# TKE AI 脚本箱

[English](README.md) | [中文](README_zh.md)

## 项目概述
本项目提供基于 Kubernetes 的 AI 大模型相关脚本，包含模型下载、部署推理服务、性能测试等模块，提供在 TKE 一站式体验 AI 相关功能的能力。

### 前置依赖
1. Kubernetes 集群（建议版本 1.28+）
2. 腾讯云 CFS 存储（或其他兼容的存储方案）
3. 可用的 GPU 机器（本项目中使用 3 * H20 节点）

### 功能

#### 模型下载

参考使用 [模型下载工具](./helm-charts/model-fetch/README.md) 下载模型到 CFS 存储中, 以便在推理服务部署过程中复用模型。

#### 部署推理服务

- [dynamo](./helm-charts/dynamo/README.md): Dynamo 是 NVIDIA 在 2025 年 GTC 大会上开源的推理框架，被设计用于在多节点分布式环境中为生成式人工智能和推理模型提供服务，支持多种推理引擎：包括 TRT-LLM、vLLM、SGLang 等等。

#### 推理服务性能压测脚本

- [LLM Benchmark](./helm-charts/benchmark/README.md)


### 示例

#### dynamo

##### 单节点 PD 分离

前提条件：
- 集群内存在一台有 8 个 GPU 的节点。

使用以下命令可以快速拉取一个单节点 PD 分离的示例, 其中包含：
-  1 个使用 4 GPU 核心，负责解码阶段的 VllmWorker。
-  4 个使用 1 GPU 核心，负责预填充阶段的 PrefillWorker。

```bash
bash examples/dynamo/single-node/deploy.sh
```

##### 三节点 PD 分离

[TODO]

### 脚本

#### 快速测试 OpenAI 格式的 API 端点

1. 脚本：[test-openai-api](./scripts/test-openai-api.sh)
2. 使用方法：

```bash
API_ENDPOINT=<your-api-endpoint> bash scripts/test-openai-api.sh

# 测试 localhost:8080
API_ENDPOINT=http://localhost:8080 bash scripts/test-openai-api.sh
```

#### 生成下载 LLM 模型的 Job

1. 脚本：[tke-llm-downloader](./scripts/tke-llm-downloader.sh)
2. 使用方法：

```bash
LLM_MODEL=<model-id> PVC_NAME=<your-pvc> bash scripts/tke-llm-downloader.sh 
```
