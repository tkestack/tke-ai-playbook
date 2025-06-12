#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

CONCURRENCY=${CONCURRENCY:-"64"}
ISL=${ISL:-"1000"}
OSL=${OSL:-"1000"}

uv run python -m sglang.bench_serving \
  --backend sglang-oai \
  --seed 100 \
  --model ${MODEL} \
  --tokenizer ${TOKENIZER} \
  --host ${HOST} --port ${PORT} \
  --dataset-name random \
  --dataset-path /sglang-workspace/dataset/ShareGPT_V3_unfiltered_cleaned_split.json \
  --random-input ${ISL} \
  --random-output ${OSL} \
  --max-concurrency ${CONCURRENCY} \
  --num-prompts $(($CONCURRENCY*10))
