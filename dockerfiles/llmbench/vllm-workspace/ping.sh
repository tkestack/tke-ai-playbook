#!/bin/bash

HOST=${HOST:-"localhost"}
PORT=${PORT:-"8000"}
MODEL=${MODEL:-"deepseek-ai/DeepSeek-R1"}

while true; do
    curl --max-time 10 -X POST "http://${HOST}:${PORT}/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'${MODEL}'",
            "messages": [
                {"role": "system", "content": "test"},
                {"role": "user", "content": "ping"}
            ],
            "temperature": 0.3,
            "max_tokens": 5,
            "top_p": 0.9
        }'
    sleep 10;
done