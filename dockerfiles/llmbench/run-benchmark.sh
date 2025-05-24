#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
PARALLEL=${PARALLEL:-"64"}
REQUEST_NUM=${REQUEST_NUM:-"640"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
MODEL_PATH=${MODEL_PATH:-"/data/${MODEL}"}
PERF="${PERF:-"vllm"}"
ISL="${ISL:-"2000"}"
OSL="${OSL:-"400"}"

if [[ "${PERF}" == "vllm" ]]; then
uv run python3 vllm-benchmarks/benchmark_serving.py \
  --backend openai-chat \
  --model ${MODEL_PATH} \
  --served-model-name ${MODEL} \
  --endpoint /v1/chat/completions \
  --dataset-name random \
  --num-prompts ${REQUEST_NUM} \
  --host ${HOST} --port ${PORT} \
  --max-concurrency ${PARALLEL} \
  --random_input_len ${ISL} \
  --random_output_len ${OSL} \
  --save-result --result-filename benchmark.json \
  --percentile-metrics ttft,tpot,itl,e2el \
  --ignore-eos

# generate markdown table for benchmark result
echo "[tke-llmbench] save table to 'benchmark_result_table.md'"
eval $(cat benchmark.json | jq -r '
  . | {output_throughput, total_token_throughput, mean_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_itl_ms, p99_itl_ms}
  | to_entries[]
  | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
')
echo "
# Benchmark Result

| Output Token Throughput (tok/s) | Mean E2E Lantency (ms) | Total Token Throughput (tok/s) | Mean TTFT (ms) | P99 TTFT (ms) | Mean ITL (ms) | P99 ITL (ms) |
|---------------------------------|------------------------|--------------------------------|----------------|---------------|---------------|--------------|
| ${output_throughput} | ${mean_e2el_ms} | ${total_token_throughput} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_itl_ms} | ${p99_itl_ms} |
" > benchmark_result_table.md

elif [[ "${PERF}" == "sglang" ]]; then
uv run python -m sglang.bench_serving \
  --backend sglang \
  --seed 100 \
  --model ${MODEL} \
  --tokenizer ${MODEL_PATH} \
  --host ${HOST} --port ${PORT}
  --dataset-name random \
  --num-prompts ${REQUEST_NUM} \
  --random-input ${ISL} \
  --random-output ${OSL} \
  --max-concurrency ${PARALLEL}
elif [[ "${PERF}" == "genai-perf" ]]; then
uv run genai-perf profile \
  --model ${MODEL} \
  --tokenizer ${MODEL_PATH} \
  --service-kind openai \
  --endpoint-type chat \
  --endpoint /v1/chat/completions \
  --streaming \
  --url http://${HOST}:${PORT} \
  --synthetic-input-tokens-mean ${ISL} \
  --synthetic-input-tokens-stddev 0 \
  --output-tokens-mean ${OSL} \
  --output-tokens-stddev 0 \
  --extra-inputs max_tokens:${OSL} \
  --extra-inputs min_tokens:${OSL} \
  --extra-inputs ignore_eos:true \
  --concurrency ${PARALLEL} \
  --request-count ${REQUEST_NUM} \
  --warmup-request-count $(($PARALLEL*2)) \
  --num-dataset-entries $(($PARALLEL*12)) \
  --random-seed 100 \
  -- \
  -v \
  --max-threads 256 \
  -H 'Authorization: Bearer NOT USED' \
  -H 'Accept: text/event-stream'
elif [[ "${PERF}" == "evalscope" ]]; then
echo "the parameter OSL='${OSL}' and ISL='${ISL}' is not used in evalscope."
uv run evalscope perf \
  --url "http://${HOST}:${PORT}/v1/chat/completions" \
  --parallel ${PARALLEL} \
  --model ${MODEL} \
  --number ${REQUEST_NUM} \
  --api openai \
  --dataset openqa \
  --stream
else
echo "Unsupported perf: ${PERF}"
exit 1
fi