#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "structlog",
#     "typer",
# ]
# ///


import typer
import json
import structlog

logger = structlog.get_logger()
app = typer.Typer()

def print_config():
    print(
"""
configVersion: v1
kubernetes:
- apiVersion: v1
  kind: Node
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
"""
)

def parse_binding_context_path(binding_context_path: str) -> dict:
    with open(binding_context_path, "r") as f:
        return json.load(f)

@app.command()
def main(
    config: bool = typer.Option(default=False),
    binding_context_path: str = typer.Option(default="", envvar="BINDING_CONTEXT_PATH")
):
    if config:
        print_config()
        return

    param = parse_binding_context_path(binding_context_path)
    logger.info(param)


if __name__ == "__main__":
    structlog.configure(processors=[structlog.processors.JSONRenderer()])
    logger.info("initializd logger")
    app()
