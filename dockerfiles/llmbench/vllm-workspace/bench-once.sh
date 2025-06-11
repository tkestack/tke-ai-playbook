#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

CONCURRENCY=${CONCURRENCY:-"64"}
ISL=${ISL:-"1000"}
OSL=${OSL:-"1000"}

RESULT_FILENAME=${RESULT_FILENAME:-"benchmark_result_${ISL}_${OSL}_c${CONCURRENCY}.md"}

mkdir -p /tmp/llmbench

uv run python3 vllm-benchmarks/benchmark_serving.py \
  --backend openai-chat \
  --model ${TOKENIZER} \
  --served-model-name ${MODEL} \
  --host ${HOST} --port ${PORT} \
  --endpoint /v1/chat/completions \
  --dataset-name random \
  --random_input_len ${ISL} \
  --random_output_len ${OSL} \
  --max-concurrency ${CONCURRENCY} \
  --num-prompts $(($CONCURRENCY*10)) \
  --save-result --result-filename /tmp/llmbench/bench-once_${ISL}_${OSL}_c${CONCURRENCY}.json \
  --percentile-metrics ttft,tpot,itl,e2el \
  --ignore-eos

# generate markdown table for benchmark result
eval $(cat /tmp/llmbench/bench-once_${ISL}_${OSL}_c${CONCURRENCY}.json | jq -r '
. | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
| to_entries[]
| "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
')
echo "[tke-llmbench] save result to '${RESULT_FILENAME}'"
echo "# Benchmark Result

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|
| ${CONCURRENCY} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |
" > ${RESULT_FILENAME}
