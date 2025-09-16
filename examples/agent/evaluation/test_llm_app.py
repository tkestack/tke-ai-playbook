import os
import logging
import pytest
import datetime as dt
from typing import Any

from deepeval import assert_test
from deepeval.models import DeepEvalBaseLLM
from deepeval.test_case import LLMTestCase, ToolCall
from deepeval.metrics import TaskCompletionMetric
from langfuse import Langfuse
from langfuse.api import TraceWithDetails
from langchain_openai import ChatOpenAI
from deepeval.dataset import EvaluationDataset


class DeepEvalOpenAI(DeepEvalBaseLLM):
    def __init__(self, model):
        self.model = model

    def load_model(self):
        return self.model

    def generate(self, prompt: str) -> str:
        chat_model = self.load_model()
        return chat_model.invoke(prompt).content

    async def a_generate(self, prompt: str) -> str:
        chat_model = self.load_model()
        res = await chat_model.ainvoke(prompt)
        return res.content

    def get_model_name(self):
        return "Custom Azure OpenAI Model"


# 拉取 traces
def fetch_traces(langfuse_cli: Any, lookback_minutes: int) -> list[TraceWithDetails]:
    now_timestamp = dt.datetime.now(dt.UTC)
    from_timestamp = now_timestamp - dt.timedelta(minutes=lookback_minutes)
    try:
        response = langfuse_cli.fetch_traces(from_timestamp=from_timestamp, to_timestamp=now_timestamp)
        return response.data
    except Exception as e:
        print(f"Failed to get traces: {e}")
        return []


# 使用 langchain sdk 自定义 llm
def get_model(model_name: str) -> DeepEvalBaseLLM:
    model = ChatOpenAI(
        model=model_name,
        temperature=0,
        max_tokens=None,
        timeout=None,
        max_retries=2,
        api_key=os.getenv("OPENAI_API_KEY"),
        base_url=os.getenv("OPENAI_API_BASE"),
    )
    return DeepEvalOpenAI(model=model)


# Get keys for your project from the project settings page
os.environ["LANGFUSE_PUBLIC_KEY"] = "pk-lf-xxxxxx"  # your langfuse public key
os.environ["LANGFUSE_SECRET_KEY"] = "sk-lf-xxxxxx"  # your langfuse secret key
os.environ["LANGFUSE_HOST"] = "http://xx.xx.xx.xx"  # your langfuse host
os.environ["DEEPEVAL_RESULTS_FOLDER"] = "/Users/deepeval_result"  # 本地保存评估结果路径

llm = get_model(model_name=os.getenv("LLM_ID"))

metric = TaskCompletionMetric(
    threshold=0.7,
    model=llm,
    include_reason=True
)

langfuse = Langfuse()
lookback_minutes = 30
traces = fetch_traces(langfuse_cli=langfuse, lookback_minutes=lookback_minutes)
logging.info(f"Fetched {len(traces)} traces for last {lookback_minutes} minutes.")

test_cases = []

for t in traces:
    tools_called_map = {}
    tools_called_list = []
    actual_output = ""
    user_input = t.input["messages"]

    if isinstance(t.output, str):
        logging.error(t)
    elif isinstance(t.output, dict) and "messages" in t.output:
        for message in t.output["messages"]:
            tool_calls = message.get("tool_calls", [])
            if isinstance(tool_calls, list) and len(tool_calls) > 0:
                for tool_call in tool_calls:
                    tools_called_map[tool_call["id"]] = ToolCall(
                        name=tool_call["name"],
                        input_parameters=tool_call["args"],
                        output=None,
                    )
            if message["type"] == "tool":
                tool_call_id = message.get("tool_call_id")
                if tool_call_id in tools_called_map:
                    tools_called_map[tool_call_id].output = message["content"]
            if message["type"] == "ai" and message["response_metadata"]["finish_reason"] == "stop":
                actual_output = message["content"]

        for _, v in tools_called_map.items():
            tools_called_list.append(v)

        test_case = LLMTestCase(
            input=user_input,
            actual_output=actual_output,
            tools_called=tools_called_list,
        )
        test_cases.append(test_case)
        dataset = EvaluationDataset(test_cases=test_cases)

logging.info(f"Got {len(test_cases)} test cases.")


# Loop through test cases
@pytest.mark.parametrize("test_case", dataset)
def test_llm_app(test_case: LLMTestCase):
    assert_test(test_case, [metric])

# RUN CMD
# deepeval test run llm-app-eval/test_llm_app.py -i
