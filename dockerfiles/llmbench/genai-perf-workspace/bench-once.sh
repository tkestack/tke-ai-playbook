#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

CONCURRENCY=${CONCURRENCY:-"64"}
ISL=${ISL:-"1000"}
OSL=${OSL:-"1000"}

# NOTE: For Dynamo HTTP OpenAI frontend, use `nvext` for fields like
# `ignore_eos` since they are not in the official OpenAI spec.
uv run genai-perf profile \
  --model ${MODEL} \
  --tokenizer ${TOKENIZER} \
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
  --extra-inputs "{\"nvext\":{\"ignore_eos\":true}}" \
  --concurrency ${CONCURRENCY} \
  --request-count $(($CONCURRENCY*10)) \
  --warmup-request-count $(($CONCURRENCY*2)) \
  --num-dataset-entries $(($CONCURRENCY*12)) \
  --random-seed 100 \
  -- \
  -v \
  --max-threads 256 \
  -H 'Authorization: Bearer NOT USED' \
  -H 'Accept: text/event-stream'
