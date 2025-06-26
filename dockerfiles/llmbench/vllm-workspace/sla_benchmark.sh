#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}

ISL=${ISL:-"2500"}
OSL=${OSL:-"500"}
TTFT=${TTFT:-"5000"}
TPOT=${TPOT:-"100"}
OUTPUT_RESULT_FILE=${OUTPUT_RESULT_FILE:-"sla_ttft${TTFT}_tpot${TPOT}_benchmark_result_${ISL}_${OSL}.md"}

TEMP_DIR=$(mktemp -d)
echo "[tke-llmbench] the result will save to '${OUTPUT_RESULT_FILE}'"
echo "# Benchmark Result (ISL:OSL=${ISL}:${OSL})

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|" > ${OUTPUT_RESULT_FILE}

concurrency=1
while true; do
    set -x
    
    uv run python3 vllm-benchmarks/benchmark_serving.py \
        --backend openai-chat \
        --model ${TOKENIZER} \
        --served-model-name ${MODEL} \
        --host ${HOST} --port ${PORT} \
        --endpoint /v1/chat/completions \
        --dataset-name random \
        --random_input_len ${ISL} \
        --random_output_len ${OSL} \
        --concurrency ${concurrency} \
        --request_timeout ${TTFT} \
        --request_timeout_per_output_token ${TPOT} \
        --output_dir ${TEMP_DIR} \
        --output_result_file ${OUTPUT_RESULT_FILE} \
        --output_result_file_append
    set +x
    
    eval $(cat /tmp/llmbench/bench_${ISL}_${OSL}_c${concurrency}.json | jq -r '
    . | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
    | to_entries[]
    | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
    ')
    echo "| ${concurrency} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |" >> ${OUTPUT_RESULT_FILE}

    if [ ${mean_ttft_ms} -gt ${TTFT} ]; then
        echo "[concurrency:${concurrency}] The mean_ttft_ms is ${mean_ttft_ms}, which is greater than SLA ${TTFT} ms."
        break
    fi
    if [ ${mean_tpot_ms} -gt ${TPOT} ]; then
        echo "[concurrency:${concurrency}] The mean_tpot_ms is ${mean_tpot_ms}, which is greater than SLA ${TPOT} ms."
        break
    fi
    echo "[concurrency:${concurrency}] The mean_ttft_ms is ${mean_ttft_ms}, which is less than SLA ${TTFT} ms."
    echo "[concurrency:${concurrency}] The mean_tpot_ms is ${mean_tpot_ms}, which is less than SLA ${TPOT} ms."

    if [ ${concurrency} -ge 64 ]; then
        concurrency=$((${concurrency} + 8))
    else
        concurrency=$((${concurrency} * 2))
    fi
    echo "increase concurrency to ${concurrency}"
done


