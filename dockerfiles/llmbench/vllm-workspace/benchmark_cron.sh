#!/bin/bash

# Default values
PEAK_HOURS="9-10,13-15"
MAX_CONCURRENCY="256"
MIN_CONCURRENCY="16"
HOST="localhost"
PORT="8000"
MODEL="deepseek-ai/DeepSeek-R1"
TOKENIZER="/workspace/tokenizer/${MODEL}"
ISL="1000"
OSL="1000"
TIMEZONE="$(date +%Z)"  # Default to system timezone
OUTPUT_RESULT_FILE="benchmark_result_${ISL}_${OSL}.md"

# Signal handling variables
should_exit=0

# Function to handle SIGINT (Ctrl+C)
handle_sigint() {
    echo "\nReceived interrupt signal (Ctrl+C), exiting gracefully..."
    should_exit=1
}

# Trap SIGINT signal
trap handle_sigint SIGINT

# Function to print help message
print_help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Examples: $0 \\"
  echo "  --host localhost \\"
  echo "  --port 8000 \\"
  echo "  --model Qwen/Qwen3-32B \\"
  echo "  --tokenizer /workspace/tokenizer/Qwen/Qwen3-32B \\"
  echo "  --peak-hours 9-10,13-15 \\"
  echo "  --timezone Asia/Shanghai"
  echo 
  echo "Options:"
  echo "  --peak-hours <start-end>           Peak hours range (default: ${PEAK_HOURS})"
  echo "  -max, --max-concurrency <int>      Base concurrency during peak hours (default: ${MAX_CONCURRENCY})"
  echo "  -min, --min-concurrency <int>      Base concurrency during off-peak hours (default: ${MIN_CONCURRENCY})"
  echo "  --timezone <tz>                    Timezone for hour calculation (default: ${TIMEZONE})"
  echo "  --host <host>                      Target host for inference requests (default: ${HOST})"
  echo "  --port <port>                      Target port for inference requests (default: ${PORT})"
  echo "  --model <model_id>                 Model ID to benchmark (default: ${MODEL})"
  echo "  --tokenizer <path>                 Tokenizer path (default: ${TOKENIZER})"
  echo "  -isl, --input-seq-len <int>        Input sequence length (default: ${ISL})"
  echo "  -osl, --output-seq-len <int>       Output sequence length (default: ${OSL})"
  echo "  -h, --help                         Show this help message and exit"
  exit 0
}


# Function to get current hour with timezone support
get_current_hour() {
  date +%-H
}

# Function to check if current hour is within any peak range
is_peak_hour() {
  local current_hour=$1
  for range in "${PEAK_RANGES[@]}"; do
    IFS='-' read -r start end <<< "${range}"
    if [[ ${current_hour} -ge ${start} && ${current_hour} -le ${end} ]]; then
      return 0
    fi
  done
  return 1
}

# Function to calculate distance to the nearest peak hour
calculate_distance_to_peak() {
  local current_hour=$1
  local min_distance=24  # Initialize with maximum possible distance

  for range in "${PEAK_RANGES[@]}"; do
    IFS='-' read -r peak_start peak_end <<< "${range}"

    # Calculate distance to peak period start (handles both before and after cases)
    x=${peak_start}
    y=${current_hour}
    distance_to_start_1=$(( ($y - $x + 24) % 24 ))
    distance_to_start_2=$(( ($x - $y + 24) % 24 ))
    if [[ ${distance_to_start_1} -lt ${distance_to_start_2} ]]; then
      distance_to_start=${distance_to_start_1}
    else
      distance_to_start=${distance_to_start_2}
    fi
    
    # Calculate distance to peak period end (handles both before and after cases)
    x=${peak_end}
    y=${current_hour}
    distance_to_end_1=$(( ($y - $x + 24) % 24 ))
    distance_to_end_2=$(( ($x - $y + 24) % 24 ))
    if [[ ${distance_to_end_1} -lt ${distance_to_end_2} ]]; then
      distance_to_end=${distance_to_end_1}
    else
      distance_to_end=${distance_to_end_2}
    fi
    
    # The actual distance is the minimum of these two values
    # This covers cases where current time is before, during or after the peak period
    if [[ ${distance_to_start} -lt ${distance_to_end} ]]; then
      current_distance=${distance_to_start}
    else
      current_distance=${distance_to_end}
    fi
    
    # Keep track of the smallest distance across all peak ranges
    if [[ ${current_distance} -lt ${min_distance} ]]; then
      min_distance=${current_distance}
    fi
  done

  echo ${min_distance}
}

# Function to run the benchmark
run_benchmark() {
  local concurrency=$1
  local temp_dir=$(mktemp -d)
  local result_file="${temp_dir}/bench_${ISL}_${OSL}_c${concurrency}.json"
  # Initialize results file
  echo "# Benchmark Result (ISL:OSL=${ISL}:${OSL})" > ${OUTPUT_RESULT_FILE}
  echo "| Concurrency | Request Throughput | Output Throughput | Mean E2EL (ms) | P99 E2EL (ms) | Mean TTFT (ms) | P99 TTFT (ms) | Mean TPOT (ms) | P99 TPOT (ms) |" >> ${OUTPUT_RESULT_FILE}
  echo "|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|" >> ${OUTPUT_RESULT_FILE}


  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Running benchmark with concurrency: ${concurrency}"
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
      --ignore-eos 2>&1 > /dev/null
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] Finshed benchmark with concurrency: ${concurrency}"

  # Parse and log results
  eval $(cat ${result_file} | jq -r '
  . | {request_throughput, output_throughput, mean_e2el_ms, p99_e2el_ms, mean_ttft_ms, p99_ttft_ms, mean_tpot_ms, p99_tpot_ms}
  | to_entries[]
  | "\(.key)=\(.value | if type == "number" then (. * 100 | round) / 100 else . end)"
  ')
  echo "| ${concurrency} | ${request_throughput} | ${output_throughput} | ${mean_e2el_ms} | ${p99_e2el_ms} | ${mean_ttft_ms} | ${p99_ttft_ms} | ${mean_tpot_ms} | ${p99_tpot_ms} |" >> ${OUTPUT_RESULT_FILE}
}

# Function to precompute base_concurrency for all hours
precompute_concurrency() {
  for hour in {0..23}; do
    # Check if hour is within any peak range
    if is_peak_hour ${hour}; then
      HOURLY_CONCURRENCY[$hour]=${MAX_CONCURRENCY}
    else
      distance=$(calculate_distance_to_peak ${hour})
      # Calculate base concurrency
      HOURLY_CONCURRENCY[$hour]=$(( ${MIN_CONCURRENCY} + ( (${MAX_CONCURRENCY} - ${MIN_CONCURRENCY}) / 12 * (10 - ${distance})) ))
    fi
  done
  
  # Print hourly concurrency
  echo "Hourly Base Concurrency Preview:"
  for hour in {0..23}; do
    printf "Hour %2d: %3d\n" ${hour} ${HOURLY_CONCURRENCY[${hour}]}
  done
}

# Global variables
declare -a HOURLY_CONCURRENCY

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --timezone)
      TIMEZONE="$2"
      shift 2
      ;;
    --peak-hours)
      PEAK_HOURS="$2"
      shift 2
      ;;
    -max|--max-concurrency)
      MAX_CONCURRENCY="$2"
      shift 2
      ;;
    -min|--min-concurrency)
      MIN_CONCURRENCY="$2"
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
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

export TZ=${TIMEZONE}

# Split PEAK_HOURS into an array of ranges
IFS=',' read -ra PEAK_RANGES <<< "${PEAK_HOURS}"

# Precompute and show hourly concurrency
precompute_concurrency

# Simulate business tides with dynamic concurrency
while [[ ${should_exit} -eq 0 ]]; do
    current_hour=$(get_current_hour)
    base_concurrency=${HOURLY_CONCURRENCY[${current_hour}]}
    
    # Add random spikes (毛刺) to concurrency
    spike=$((RANDOM % 16))
    concurrency=$((base_concurrency + spike))

    # Run the benchmark
    run_benchmark ${concurrency}
done
