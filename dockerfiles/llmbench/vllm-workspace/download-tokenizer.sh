#!/bin/bash

# Usage: bash download-tokenizer.sh <model-id>

MODEL=$1

uv run modelscope download --model "${MODEL}" --include '*.json' --local_dir "/workspace/tokenizer/${MODEL}"
