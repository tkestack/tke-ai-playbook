import os
import asyncio

from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent
from langchain_mcp_adapters.client import MultiServerMCPClient
from langfuse.callback import CallbackHandler


# react agent + mcp
async def multi_tool_demo(model: ChatOpenAI, query: str, config: dict):
    async with MultiServerMCPClient({
        "math": {
            "command": "python",
            # Make sure to update to the full absolute path to your math.py file
            "args": ["math_server.py"],
            "transport": "stdio",
        },
    }) as client:
        agent = create_react_agent(model, client.get_tools())
        try:
            response = await agent.ainvoke({"messages": query}, config=config)
            print(f"\n工具调用结果（query: {query}）：")
            for m in response['messages']:
                m.pretty_print()
        except Exception as e:
            print(f"工具调用出错: {e}")

if __name__ == "__main__":
    # get keys for your project
    os.environ["LANGFUSE_PUBLIC_KEY"] = "pk-lf-***"  # your langfuse public key
    os.environ["LANGFUSE_SECRET_KEY"] = "sk-lf-***"  # your langfuse secret key
    os.environ["LANGFUSE_HOST"] = "http://xx.xx.xx.xx"  # your langfuse host

    query = "今有雉兔同笼，上有三十五头，下有九十四足，问雉兔各几何？(请使用我给你提供的工具)"

    # init model
    model = ChatOpenAI(
        model="<YOUR_LLM_ID>",
        api_key=os.getenv("OPENAI_API_KEY"),
        base_url=os.getenv("OPENAI_API_BASE"),
    )

    # Initialize Langfuse CallbackHandler for Langchain (tracing)
    langfuse_handler = CallbackHandler()
    config = {"callbacks": [langfuse_handler]}

    # invoke agent
    async def run_tools():
        await multi_tool_demo(model=model, query=query, config=config)

    asyncio.run(run_tools())
