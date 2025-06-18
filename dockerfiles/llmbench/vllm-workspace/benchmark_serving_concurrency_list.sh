#!/bin/bash
set -euo pipefail

# Default values
HOST="localhost"
PORT="8000"
MODEL="deepseek-ai/DeepSeek-R1"
TOKENIZER="/workspace/tokenizer/${MODEL}"
ISL="1000"
OSL="1000"
BENCH_LOOP="1"
OUTPUT_RESULT_FILE="benchmark_result_${ISL}_${OSL}.md"
CONCURRENCY_LIST="1,2,4,8,16,32,64,128"

# Function to print help message
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --host <host>                             Target host for inference requests (default: ${HOST})"
  echo "  --port <port>                             Target port for inference requests (default: ${PORT})"
  echo "  --model <model_id>                        Model ID to benchmark (default: ${MODEL})"
  echo "  --tokenizer <path>                        Tokenizer path (default: ${TOKENIZER})"
  echo "  -isl, --input-sequence-length <int>       Input sequence length (default: ${ISL})"
  echo "  -osl, --output-sequence-length <int>      Output sequence length (default: ${OSL})"
  echo "  --bench-loop <int>                        Number of benchmark loops (default: ${BENCH_LOOP})"
  echo "  --concurrency <list>                      Comma-separated concurrency levels (default: ${CONCURRENCY_LIST})"
  echo "  -h, --help                                Show this help message and exit"
  echo
  exit 0
}

# Function to parse command line arguments
get_options() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --host)
        HOST="$2"
        shift 2
        ;;
      --port)
        PORT="$2"
        shift 2
        ;;
      --model)
        MODEL="$2"
        shift 2
        ;;
      --tokenizer)
        TOKENIZER="$2"
        shift 2
        ;;
      -isl|--input-sequence-length)
        ISL="$2"
        shift 2
        ;;
      -osl|--output-sequence-length)
        OSL="$2"
        shift 2
        ;;
      --bench-loop)
        BENCH_LOOP="$2"
        shift 2
        ;;
      --concurrency)
        CONCURRENCY_LIST="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 1
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
  done

  OUTPUT_RESULT_FILE="benchmark_result_${ISL}_${OSL}.md"
}


# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to validate concurrency values
validate_concurrency() {
  for val in "${concurrency_array[@]}"; do
    if ! [[ "$val" =~ ^[0-9]+$ ]] || [ "$val" -le 0 ]; then
      log "Error: Invalid concurrency value '$val'. Must be a positive integer."
      exit 1
    fi
  done
}

# Function to run the benchmark
run_benchmark() {
    local concurrency=$1
    local temp_dir=$(mktemp -d)
    local result_file="${temp_dir}/bench_${ISL}_${OSL}_c${concurrency}.json"

    log "Running benchmark with concurrency: ${concurrency}"
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
        --save-result --result-filename ${result_file} \
        --percentile-metrics ttft,tpot,itl,e2el \
        --ignore-eos
    { set +x; } 2>/dev/null

    # Parse and log results
    eval $(cat ${result_file} | jq -r '
    . | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
    | to_entries[]
    | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
    ')
    echo "| ${concurrency} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |" >> ${OUTPUT_RESULT_FILE}
}

# Main script execution
main() {
    # Parse command line arguments
    get_options "$@"

    IFS=',' read -r -a concurrency_array <<< "${CONCURRENCY_LIST}"
    validate_concurrency

    log "Starting benchmark. Results will be saved to '${OUTPUT_RESULT_FILE}'"
    echo "# Benchmark Result (ISL:OSL=${ISL}:${OSL})

| Concurrency | Reqeuest Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Lantency (ms)  | P99 E2E Lantency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:--------------------------:|:-------------------------------:|:-----------------------:|:---------------------:|:--------------:|:-------------:|:-------------:|:------------:|" > ${OUTPUT_RESULT_FILE}

    for i in $(seq 1 ${BENCH_LOOP}); do
        log "Benchmark loop ${i}/${BENCH_LOOP}"
        for concurrency in "${concurrency_array[@]}"; do
            run_benchmark ${concurrency}
        done
    done

    log "Benchmark completed. Results saved to '${OUTPUT_RESULT_FILE}'"
    cat ${OUTPUT_RESULT_FILE}
}

# Execute the main function
main "$@"