# llmbench

llmbench 整合了一些推理引擎压测工具，包括：
- vllm: /workspace
- sglang: /sglang-workspace
- genai-perf: /genai-perf-workspace
- evalscope: /evalscope-workspace

## 基准测试

对于在线推理服务的性能，使用 bench.sh 进行基准测试。
bench.sh 脚本会测试并发数 1, 2, 4, 8, 16, 32, 64, 128 的情况，包含以下输入输出比例:
- ISL:OSL=3000:150
- ISL:OSL=1000:1000
- ISL:OSL=500:1000

同时会输出一个 markdown 格式的 table 作为结果展示

```bash
cd /workspace

export HOST=localhost 
export PORT=8000 
export MODEL=deepseek-ai/DeepSeek-R1 
export TOKENIZER=/workspace/tokenizer/deepseek-ai/DeepSeek-R1 
bash bench.sh
```

参考结果（默认保存在 benchmark_result_${ISL}_${OSL}.md）

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|
| 1 | 0.03 | 33.32 | 30010.56 | 30202.48 | 158.64 | 167.93 | 29.88 | 30.07 |
| 2 | 0.06 | 57.96 | 34507.17 | 34743.53 | 233.92 | 305.74 | 34.31 | 34.59 |
| 4 | 0.11 | 110 | 36362.91 | 37012.77 | 370.24 | 453.67 | 36.03 | 36.76 |
| 8 | 0.2 | 204.05 | 39201.31 | 39719.73 | 486.31 | 846.82 | 38.75 | 39.37 |
| 16 | 0.35 | 352.11 | 45430.89 | 46466 | 615.43 | 1620.85 | 44.86 | 45.54 |
| 32 | 0.59 | 593.36 | 53908.9 | 56004.3 | 788.2 | 3114.6 | 53.17 | 54.67 |
| 64 | 0.93 | 932.26 | 68607.6 | 73112.96 | 1035.6 | 5904.52 | 67.64 | 68.83 |
| 128 | 1.44 | 1441.79 | 88679.14 | 98840.42 | 1426 | 11664.79 | 87.34 | 89.41 |
