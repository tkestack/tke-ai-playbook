#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}
TOKENIZER=${TOKENIZER:-"/workspace/tokenizer/${MODEL}"}
ISL=${ISL:-"1000"}
OSL=${OSL:-"1000"}
OUTPUT_RESULT_FILE=${OUTPUT_RESULT_FILE:-"benchmark_result_${ISL}_${OSL}.md"}

BENCH_LOOP=${BENCH_LOOP:-"1"}

mkdir -p /tmp/llmbench
echo "[tke-llmbench] the result will save to '${OUTPUT_RESULT_FILE}'"
echo "# Benchmark Result (ISL:OSL=${ISL}:${OSL})

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|" > ${OUTPUT_RESULT_FILE}

for i in {1..${BENCH_LOOP}}; do
    for concurrency in 1 2 4 8 16 32 64 128; do
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
            --max-concurrency ${concurrency} \
            --num-prompts $((${concurrency}*10)) \
            --save-result --result-filename /tmp/llmbench/bench_${ISL}_${OSL}_c${concurrency}.json \
            --percentile-metrics ttft,tpot,itl,e2el \
            --ignore-eos
        set +x

        eval $(cat /tmp/llmbench/bench_${ISL}_${OSL}_c${concurrency}.json | jq -r '
        . | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
        | to_entries[]
        | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
        ')
        echo "| ${concurrency} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |" >> ${OUTPUT_RESULT_FILE}
    done
done

cat ${OUTPUT_RESULT_FILE}