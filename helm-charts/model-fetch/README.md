# model-fetch

[English](README.md) | [中文](README_zh.md)

`model-fetch` facilitates large language model (LLM) downloads from huggingface.co or modelscope.cn to PVC in Tencent Kubernetes Engine (TKE).

## Configuration Guide

### Core Parameters

| Key | Description | Default |
|-----|-------------|---------|
| pvcName | PVC name used to store the LLM model. | ai-model |
| storageClassName | Name of the storage class. | cfs-ai |
| storageSize | Storage capacity allocated to the PVC. | 100Gi |
| jobName | Name of the job for downloading the LLM model. | vllm-download-model |
| modelName | LLM model to be downloaded. | deepseek-ai/DeepSeek-R1-Distill-Qwen-7B |
| useModelscope | Source selection for model download (1=Modelscope, 0=HuggingFace). | 1 |

## Usage

1. **Storage Preparation**:  
   Create a StorageClass named `cfs-ai` via Tencent Cloud Console.

2. **Model Download**:  
   Execute this command to:
   - Create PVC `ai-model` using StorageClass `cfs-ai`
   - Launch download job for model `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B`

```bash
helm install model-fetch . -f values.yaml \
  --set modelName=deepseek-ai/DeepSeek-R1-Distill-Qwen-7B \
  --set pvcName=ai-model \
  --set storageClassName=cfs-ai
```

You can monitor the download progress by checking the logs of the job's corresponding Pod.

```bash
$ kubectl logs -f vllm-download-model-pb2r8
Downloading [model-00004-of-000163.safetensors]:  16%|█▌        | 648M/4.01G [13:47<1:23:01, 727kB/s]
Downloading [model-00005-of-000163.safetensors]:  30%|██▉       | 1.19G/4.01G [13:48<1:01:25, 820kB/s]
Downloading [model-00001-of-000163.safetensors]:  20%|██        | 0.99G/4.87G [13:48<41:47, 1.66MB/s]
Downloading [model-00006-of-000163.safetensors]:  27%|██▋       | 1.11G/4.07G [13:47<30:32, 1.73MB/s]
Downloading [model-00007-of-000163.safetensors]:   7%|▋         | 274M/4.01G [00:58<10:11, 6.57MB/s]
Downloading [model-00003-of-000163.safetensors]:  45%|████▌     | 1.81G/4.01G [13:47<44:38, 879kB/s]
```
