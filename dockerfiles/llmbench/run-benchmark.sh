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
  --ignore-eos
elif [[ "${PERF}" == "sglang" ]]; then
echo "the parameter REQUEST_NUM='${REQUEST_NUM}' is not used in sglang."
uv run python -m sglang.bench_one_batch_server \
  --model-path ${MODEL_PATH} \
  --base-url http://${HOST}:${PORT} \
  --batch-size ${PARALLEL} \
  --input-len ${ISL} \
  --output-len ${OSL} \
  --skip-warmup
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