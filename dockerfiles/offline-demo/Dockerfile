FROM python:3.11-slim-bookworm
WORKDIR /workspace
COPY --from=ghcr.io/astral-sh/uv:0.6.17 /uv /uvx /bin/

RUN apt-get update -y
RUN apt-get install -y bash git vim build-essential

RUN pip install modelscope
RUN pip install -U "huggingface_hub[cli]"

COPY .python-version .
COPY pyproject.toml .
COPY uv.lock .
RUN uv sync

COPY . .

ENTRYPOINT ["uv", "run", "python", "cos_kafka.py"]
CMD ["--help"]
