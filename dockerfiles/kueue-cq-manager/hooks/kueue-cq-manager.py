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
  executeHookOnEvent: ["Added", "Modified", "Deleted"]
  jqFilter: "{ name: .metadata.name, labels: .metadata.labels, capacity: .status.capacity }"
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

    binding_context_content = parse_binding_context_path(binding_context_path)
    objects = []
    for content in binding_context_content:
        if content['type'] == 'Synchronization':
            for item in content['objects']:
                objects.append({
                    'name': item['filterResult']['name'],
                    'labels': item['filterResult']['labels'],
                    'capacity': item['filterResult']['capacity']
                })
        elif content['type'] == 'Event':
            objects.append({
                'name': content['filterResult']['name'],
                'labels': content['filterResult']['labels'],
                'capacity': content['filterResult']['capacity']
            })
        else:
            print(f"Unknown binding type '{content['type']}'")
            return
    print(objects)

if __name__ == "__main__":
    app()
