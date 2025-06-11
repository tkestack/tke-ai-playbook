#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}

CONCURRENCY=${CONCURRENCY:-"64"}

uv run evalscope perf \
  --url "http://${HOST}:${PORT}/v1/chat/completions" \
  --model ${MODEL} \
  --parallel ${CONCURRENCY} \
  --number $(($CONCURRENCY*10)) \
  --api openai \
  --dataset openqa \
  --stream