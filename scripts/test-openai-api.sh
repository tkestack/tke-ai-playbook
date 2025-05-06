#!/bin/bash

API_ENDPOINT=${API_ENDPOINT:-"http://localhost:8000"}

model=$(curl -s "${API_ENDPOINT}/v1/models" | jq -r '.data[0].id')


curl -X POST "${API_ENDPOINT}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
  "model": "'${model}'",
  "messages": [
    {"role": "system", "content": "你是一个AI编程助手"},
    {"role": "user", "content": "用Python实现快速排序算法"}
  ],
  "temperature": 0.3,
  "max_tokens": 512,
  "top_p": 0.9
}'
