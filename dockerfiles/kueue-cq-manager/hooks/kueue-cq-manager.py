#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "typer",
# ]
# ///


import typer
import json

app = typer.Typer()

def print_config():
    print(
"""
configVersion: v1
kubernetes:
- apiVersion: v1
  kind: Node
  executeHookOnEvent: ["Added", "Deleted"]
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
    print(param)


if __name__ == "__main__":
    app()
