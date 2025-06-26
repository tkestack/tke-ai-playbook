#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

declare -a isl_list=(3000 1000 500)
declare -a osl_list=(150 1000 1000)

for i in "${!isl_list[@]}"; do
    local isl=${isl_list[$i]}
    local osl=${osl_list[$i]}
    echo "======================================================"
    echo "   Running benchmark with 'ISL:OSL=${ISL}:${OSL}'     "
    echo "   OpenAI Server 'http://${HOST}:${PORT}'             "
    echo "   Model '${MODEL}'                                   "
    echo "   Tokenizer '${TOKENIZER}'                           "
    echo "======================================================"

    bash benchmark_serving_concurrency_list.sh \
      --host ${HOST} \
      --port ${PORT} \
      --model ${MODEL} \
      --tokenizer ${TOKENIZER} \
      -isl ${isl} \
      -osl ${osl}

    echo ""
    echo ""
    echo ""
done