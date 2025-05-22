FROM ubuntu:24.04
WORKDIR /workspace
COPY --from=ghcr.io/astral-sh/uv:0.6.17 /uv /uvx /bin/
# RUN apt-get update -y
RUN apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Check-Date=false update -y
RUN apt-get install -y bash git vim python3

RUN uv venv

# Install modelscope and huggingface
RUN uv pip install modelscope
RUN uv pip install -U "huggingface_hub[cli]"

# Install evalscope
RUN uv pip install 'evalscope[perf]' -U
RUN uv pip install uvicorn
# download openqa dataset
RUN uv run modelscope download --dataset 'AI-ModelScope/HC3-Chinese' --include 'open_qa.jsonl'

# Install vllm
RUN git clone -b v0.8.4 --depth 1 https://github.com/vllm-project/vllm.git /workspace/vllm
RUN mv /workspace/vllm/benchmarks /workspace/vllm-benchmarks && rm -rf /workspace/vllm
RUN uv pip install vllm

# install genai-perf
RUN uv pip install genai-perf

# install sglang
RUN uv pip install "sglang[all]>=0.4.6.post4"

COPY . /workspace

CMD ["bash", "-l"]
