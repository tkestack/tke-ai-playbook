#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

declare -a isl_list=(3000 1000 500)
declare -a osl_list=(150 1000 1000)

for i in "${!isl_list[@]}"; do
    ISL=${isl_list[$i]}
    OSL=${osl_list[$i]}
    echo "======================================================"
    echo "   Running benchmark with ISL:OSL=${ISL}:${OSL}...    "
    echo "======================================================"

    bash benchmark_serving_concurrency.sh

    echo ""
    echo ""
    echo ""
done