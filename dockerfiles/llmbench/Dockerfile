FROM ubuntu:24.04
COPY --from=ghcr.io/astral-sh/uv:0.7.12 /uv /uvx /bin/
RUN apt-get update -y
#RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update -y
RUN apt-get install -y bash curl git vim python3 jq

WORKDIR /workspace
RUN uv venv && \
    uv pip install -U setuptools && \
    uv pip install modelscope && \
    uv pip install -U "huggingface_hub[cli]"
# Install vllm
RUN git clone -b v0.8.4 --depth 1 https://github.com/vllm-project/vllm.git /workspace/vllm
RUN mv /workspace/vllm/benchmarks /workspace/vllm-benchmarks && rm -rf /workspace/vllm
RUN uv pip install vllm

# install sglang
WORKDIR /sglang-workspace
RUN uv venv && \
    uv pip install "sglang[runtime_common]>=0.4.7"
RUN mkdir -p /sglang-workspace/dataset
RUN curl -L https://huggingface.co/datasets/anon8231489123/ShareGPT_Vicuna_unfiltered/resolve/main/ShareGPT_V3_unfiltered_cleaned_split.json -o /sglang-workspace/dataset/ShareGPT_V3_unfiltered_cleaned_split.json

# install genai-perf
WORKDIR /genai-perf-workspace
RUN uv venv && \
    uv pip install genai-perf

# Install evalscope
WORKDIR /evalscope-workspace
RUN uv venv && \
    uv pip install -U 'evalscope[perf]' && \
    uv pip install uvicorn

WORKDIR /workspace
RUN uv pip install pandas pyarrow datasets
# download dataset
## open_qa
RUN uv run modelscope download --dataset 'AI-ModelScope/HC3-Chinese' --include 'open_qa.jsonl'
# download tokenizer
RUN uv run modelscope download --model 'deepseek-ai/DeepSeek-R1' --include '*.json' --local_dir '/workspace/tokenizer/deepseek-ai/DeepSeek-R1'
RUN uv run modelscope download --model 'deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B' --include '*.json' --local_dir '/workspace/tokenizer/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B'
RUN uv run modelscope download --model 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B' --include '*.json' --local_dir '/workspace/tokenizer/deepseek-ai/DeepSeek-R1-Distill-Qwen-7B'

COPY ./vllm-workspace /workspace
COPY ./sglang-workspace /sglang-workspace
COPY ./genai-perf-workspace /genai-perf-workspace
COPY ./evalscope-workspace /evalscope-workspace

CMD ["bash", "-l"]

