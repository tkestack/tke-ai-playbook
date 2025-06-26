# Dynamo 1P1D

4 * 8 * H20 96GB

## Image

```Dockerfile
# git clone https://github.com/ai-dynamo/dynamo.git
# git checkout v0.3.0
# git cherry-pick f7b3ccfcb2f1afa5a0b3a0d0489ed3bff3b1789c
# ./container/build.sh --make-efa --release-build
FROM ccr.ccs.tencentyun.com/tke-ai-playbook/dynamo:v0.3.0-pr1333
COPY --from=vllm/vllm-openai:v0.9.0.1 /vllm-workspace/examples/online_serving/multi-node-serving.sh /workspace/multi-node-serving.sh
```

## Config

```yaml
Common:
  model: /data/models/deepseek-ai/DeepSeek-R1
  block-size: 128
  max-model-len: 4096
  kv-transfer-config: '{"kv_connector":"DynamoNixlConnector"}'
  tensor-parallel-size: 16
  max-num-batched-tokens: 4096

Frontend:
  served_model_name: deepseek-ai/DeepSeek-R1
  endpoint: dynamo.Processor.chat/completions
  port: 8000

Processor:
  router: round-robin
  common-configs: [model, block-size]

VllmWorker:
  remote-prefill: true
  conditional-disagg: false
  compilation-config: '{"cudagraph_capture_sizes": [1, 2, 4, 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128, 136, 144, 152, 160, 168, 176, 184, 192, 200, 208, 216, 224, 232, 240, 248, 256]}'
  enable-reasoning: true
  reasoning-parser: deepseek_r1
  ServiceArgs:
    workers: 1
    resources:
      gpu: '16'
  common-configs: [model, block-size, max-model-len, kv-transfer-config, tensor-parallel-size]

PrefillWorker:
  enforce-eager: true
  ServiceArgs:
    workers: 1
    resources:
      gpu: '16'
  common-configs: [model, block-size, max-model-len, kv-transfer-config, tensor-parallel-size, max-num-batched-tokens, enforce-eager]
```

## Benchmark Result (ISL:OSL=3000:150)

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|
| 1 | 0.15 | 22.06 | 6798.05 | 7706.13 | 596.85 | 1490.01 | 41.62 | 41.73 |
| 2 | 0.33 | 43.49 | 5833.42 | 6811.13 | 605.16 | 971.57 | 40.47 | 41.01 |
| 4 | 0.58 | 85.85 | 6886.52 | 7730.57 | 666.96 | 1547.9 | 41.99 | 42.43 |
| 8 | 0.96 | 143.8 | 8082.22 | 10174.44 | 839.25 | 2907.49 | 48.76 | 49.69 |
| 16 | 1.6 | 239.94 | 9634.47 | 14303.2 | 955.28 | 5576.56 | 58.25 | 59.41 |
| 32 | 2.53 | 378.92 | 12177.73 | 20423.12 | 1978.06 | 10643.02 | 68.66 | 72.41 |
| 64 | 2.6 | 390.39 | 23603.91 | 31825.9 | 12804.34 | 21492.83 | 72.48 | 82.57 |
| 128 | 2.71 | 405.99 | 45051.74 | 52616.73 | 34351.46 | 41339.98 | 71.93 | 77.02 |

## Benchmark Result (ISL:OSL=1000:1000)

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|
| 1 | 0.02 | 23.71 | 42170.47 | 42532.82 | 346.16 | 540.49 | 41.87 | 42.25 |
| 2 | 0.05 | 47.13 | 38409.82 | 41789.88 | 346.84 | 540.01 | 40.01 | 41.49 |
| 4 | 0.1 | 95.12 | 42020.87 | 42699.99 | 357.34 | 892.35 | 41.71 | 41.86 |
| 8 | 0.17 | 167.58 | 46592.75 | 48272.2 | 420.44 | 1655.74 | 46.76 | 47.19 |
| 16 | 0.28 | 283.87 | 56210.15 | 58758.89 | 535.07 | 3186.66 | 55.73 | 58.4 |
| 32 | 0.53 | 528.38 | 59547.24 | 64284.12 | 723.85 | 6226.31 | 59.28 | 59.92 |
| 64 | 0.87 | 858.62 | 72790.39 | 84330.61 | 1082.1 | 12513.69 | 72.42 | 73.82 |
| 128 | 1.36 | 1345.37 | 92156.25 | 114674.5 | 1828.51 | 24682.93 | 91.57 | 96.94 |

## Benchmark Result (ISL:OSL=500:1000)

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|
| 1 | 0.02 | 23.74 | 42124.64 | 42227.86 | 300.86 | 305.41 | 41.87 | 41.97 |
| 2 | 0.06 | 49.83 | 36081.04 | 40183.97 | 311.43 | 496.72 | 39.82 | 40.78 |
| 4 | 0.11 | 90.2 | 34319.53 | 41391.73 | 340 | 872.66 | 40.8 | 41.09 |
| 8 | 0.17 | 157.53 | 45864.78 | 49424.88 | 417.54 | 1664.12 | 47.99 | 49.29 |
| 16 | 0.29 | 276.96 | 53183.63 | 60674.81 | 554.4 | 3281.8 | 54.98 | 58.96 |
| 32 | 0.54 | 500.75 | 56291.53 | 66380.54 | 744.87 | 6446.54 | 59.65 | 61.68 |
| 64 | 0.91 | 873.08 | 68062.95 | 81116.36 | 1152.33 | 12504.93 | 69.55 | 71.23 |
| 128 | 1.47 | 1441.31 | 84769.19 | 110952.12 | 1905.81 | 25269.48 | 84.59 | 86.33 |
