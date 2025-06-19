#!/bin/bash

# Default values
INITIAL_CONCURRENCY=16
MAX_CONCURRENCY=256
INTERVAL_SECONDS=60
HOST="localhost"
PORT="8000"
MODEL="deepseek-ai/DeepSeek-R1"
TOKENIZER="/workspace/tokenizer/${MODEL}"
ISL="1000"
OSL="1000"

# Function to print help message
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --initial-concurrency <int>    Initial concurrency level (default: ${INITIAL_CONCURRENCY})"
  echo "  --max-concurrency <int>        Maximum concurrency level (default: ${MAX_CONCURRENCY})"
  echo "  --interval <int>               Interval in seconds between concurrency increases (default: ${INTERVAL_SECONDS})"
  echo "  --host <host>                  Target host for inference requests (default: ${HOST})"
  echo "  --port <port>                  Target port for inference requests (default: ${PORT})"
  echo "  --model <model_id>             Model ID to benchmark (default: ${MODEL})"
  echo "  --tokenizer <path>             Tokenizer path (default: ${TOKENIZER})"
  echo "  -isl, --input-seq-len <int>    Input sequence length (default: ${ISL})"
  echo "  -osl, --output-seq-len <int>   Output sequence length (default: ${OSL})"
  echo "  -h, --help                     Show this help message and exit"
  exit 0
}

# Function to parse command line arguments
get_options() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --initial-concurrency)
        INITIAL_CONCURRENCY="$2"
        shift 2
        ;;
      --max-concurrency)
        MAX_CONCURRENCY="$2"
        shift 2
        ;;
      --interval)
        INTERVAL_SECONDS="$2"
        shift 2
        ;;
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
      -isl|--input-seq-len)
        ISL="$2"
        shift 2
        ;;
      -osl|--output-seq-len)
        OSL="$2"
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
}

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to run the benchmark
run_benchmark() {
  local concurrency=$1
  local temp_dir=$(mktemp -d)
  local result_file="${temp_dir}/bench_${ISL}_${OSL}_c${concurrency}.json"
  local output_result_file="benchmark_result_${ISL}_${OSL}_c${concurrency}.md"

  log "Running benchmark with concurrency: ${concurrency}"
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
    --num-prompts ${concurrency} \
    --save-result --result-filename ${result_file} \
    --percentile-metrics ttft,tpot,itl,e2el \
    --ignore-eos

  # Generate markdown table for benchmark result
  eval $(cat ${result_file} | jq -r '
  . | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
  | to_entries[]
  | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
  ')
  log "Benchmark completed. Results saved to '${output_result_file}'"
  echo "# Benchmark Result (ISL:OSL=${ISL}:${OSL})
| Concurrency | Request Throughput (req/s) | Output Token Throughput (tok/s) | Mean E2E Latency (ms) | P99 E2E Latency (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |
|:-----------:|:---------------------------:|:-------------------------------:|:---------------------:|:-------------------:|:--------------:|:-------------:|:--------------:|:-------------:|
| ${concurrency} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |
" > ${output_result_file}
}

# Main script execution
main() {
  # Parse command line arguments
  get_options "$@"

  # Initialize concurrency
  current_concurrency=${INITIAL_CONCURRENCY}

  # Run benchmark in a loop, doubling concurrency until max is reached
  while true; do
    run_benchmark ${current_concurrency}
    current_concurrency=$((current_concurrency * 2))
    if [[ ${current_concurrency} -gt ${MAX_CONCURRENCY} ]]; then
      current_concurrency=${MAX_CONCURRENCY}
    fi
    log "Waiting for ${INTERVAL_SECONDS} seconds before next run (with concurrency: ${current_concurrency})"
    sleep ${INTERVAL_SECONDS}
  done
}

# Execute the main function
main "$@"
