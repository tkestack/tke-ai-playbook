from typing import Dict, Any
from typing_extensions import Annotated
import typer
import json
from kafka import KafkaProducer, KafkaConsumer
from PIL import Image
import os
import sys

import utils
from vllm import LLM, SamplingParams
from vllm.inputs import TextPrompt
from transformers.models.auto.processing_auto import AutoProcessor

app = typer.Typer()

def generate_prompt(model: str, image: Image.Image) -> TextPrompt:
    question = (
        # '''
        # 描述图片内容
        # '''
        """
        描述图片内容，并给出图中眼睛的标注框，格式如下: 
        ```json
        [
            {
                "bbox_2d": [x1, y1, x2, y2],
                "label": "eye"
                "description": "something",
            },
            ...
        ]
        ```
        """
    )
    messages = [
        {"role": "system", "content": "You are a helpful assistant."},
        {
            "role": "user",
            "content": [
                {"type": "image", "image": "image"},
                {"type": "text", "text": question},
            ],
        },
    ]
    processor = AutoProcessor.from_pretrained(model)

    prompt = processor.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    return TextPrompt(
        prompt=prompt,
        multi_modal_data=dict(
            image=image,
        )
    )

@app.command()
def produce(
    bootstrap_servers: Annotated[str, typer.Option(envvar="BOOTSTRAP_SERVERS")],
    sasl_plain_username: Annotated[str, typer.Option(envvar="SASL_PLAIN_USERNAME")],
    sasl_plain_password: Annotated[str, typer.Option(envvar="SASL_PLAIN_PASSWORD")],
    topic_name: Annotated[str, typer.Option(envvar="TOPIC_NAME")],
    region: Annotated[str, typer.Option(envvar="COS_REGION")],
    bucket: Annotated[str, typer.Option(envvar="COS_BUCKET")],
    secret_id: str = typer.Option(default="", envvar="COS_SECRET_ID"),
    secret_key: str = typer.Option(default="", envvar="COS_SECRET_KEY"),
):
    cos = utils.CosClient(
        region=region,
        bucket=bucket,
        secret_id=secret_id,
        secret_key=secret_key,
    )

    ds = cos.read_images()
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        security_protocol="SASL_PLAINTEXT",
        sasl_mechanism="PLAIN",
        sasl_plain_username=sasl_plain_username,
        sasl_plain_password=sasl_plain_password,
    )

    for row in ds.take_all():
        pil_img = Image.fromarray(row["image"]).convert("RGB")
        w, h = pil_img.size
        pil_img_quarter = pil_img.resize((w // 4, h // 4))
        b64_img = utils.image_to_base64(pil_img_quarter)
        img_filename = os.path.basename(row["path"])

        msg_data = dict(
            filename=img_filename,
            image=b64_img,
        )
        msg = json.dumps(msg_data).encode('utf-8')
        print(f"send image '{img_filename}':'{sys.getsizeof(msg)}' to topic '{topic_name}'.")
        producer.send(topic=topic_name, value=msg)
    
    producer.close()

@app.command()
def inference(
    bootstrap_servers: Annotated[str, typer.Option(envvar="BOOTSTRAP_SERVERS")],
    sasl_plain_username: Annotated[str, typer.Option(envvar="SASL_PLAIN_USERNAME")],
    sasl_plain_password: Annotated[str, typer.Option(envvar="SASL_PLAIN_PASSWORD")],
    source_topic_name: Annotated[str, typer.Option(envvar="SOURCE_TOPIC_NAME")],
    target_topic_name: Annotated[str, typer.Option(envvar="TARGET_TOPIC_NAME")],
    consumer_group_id: Annotated[str, typer.Option(envvar="CONSUMER_GROUP_ID")],
    vllm_engine_kwargs: str = typer.Option(default='{"enable_chunked_prefill": True}')
):
    consumer = KafkaConsumer(
        source_topic_name,
        group_id=consumer_group_id,
        bootstrap_servers=bootstrap_servers,
        security_protocol="SASL_PLAINTEXT",
        sasl_mechanism="PLAIN",
        sasl_plain_username=sasl_plain_username,
        sasl_plain_password=sasl_plain_password,
        consumer_timeout_ms=30000,
    )
    producer = KafkaProducer(
        bootstrap_servers=bootstrap_servers,
        security_protocol="SASL_PLAINTEXT",
        sasl_mechanism="PLAIN",
        sasl_plain_username=sasl_plain_username,
        sasl_plain_password=sasl_plain_password,
    )


    vllm_args = json.loads(vllm_engine_kwargs)
    model = vllm_args['model']
    llm = LLM(**vllm_args)
    print("init vllm engine finished")

    for message in consumer:
        msg = json.loads(message.value)
        filename = msg['filename']
        b64_img = msg['image']
        pil_img = utils.base64_to_image(b64_img)
        w, h = pil_img.size
        pil_img_big = pil_img.resize((w * 4, h * 4))

        outputs = llm.generate(
            generate_prompt(model, pil_img_big),
            sampling_params=SamplingParams(
                temperature=0.0,
                max_tokens=4096,
            ),
        )

        generated_text = outputs[0].outputs[0].text
        result = dict(
            filename=filename,
            image=b64_img,
            answer=generated_text,
        )
        print("-" * 50)
        print(f"answer:\n{generated_text}")
        producer.send(
            topic=target_topic_name, 
            value=json.dumps(result).encode('utf-8')
        )
        producer.flush()
    
@app.command()
def draw(
    bootstrap_servers: Annotated[str, typer.Option(envvar="BOOTSTRAP_SERVERS")],
    sasl_plain_username: Annotated[str, typer.Option(envvar="SASL_PLAIN_USERNAME")],
    sasl_plain_password: Annotated[str, typer.Option(envvar="SASL_PLAIN_PASSWORD")],
    topic_name: Annotated[str, typer.Option(envvar="TOPIC_NAME")],
    consumer_group_id: Annotated[str, typer.Option(envvar="CONSUMER_GROUP_ID")],
    region: Annotated[str, typer.Option(envvar="COS_REGION")],
    bucket: Annotated[str, typer.Option(envvar="COS_BUCKET")],
    secret_id: str = typer.Option(default="", envvar="COS_SECRET_ID"),
    secret_key: str = typer.Option(default="", envvar="COS_SECRET_KEY"),
    draw_type: str = typer.Option(default="bboxes", envvar="DRAW_TYPE"),
):
    consumer = KafkaConsumer(
        topic_name,
        group_id=consumer_group_id,
        bootstrap_servers=bootstrap_servers,
        security_protocol="SASL_PLAINTEXT",
        sasl_mechanism="PLAIN",
        sasl_plain_username=sasl_plain_username,
        sasl_plain_password=sasl_plain_password,
        consumer_timeout_ms=30000,
    )
    cos = utils.CosClient(
        region=region,
        bucket=bucket,
        secret_id=secret_id,
        secret_key=secret_key,
    )

    for message in consumer:
        msg = json.loads(message.value)
        filename = msg['filename']
        b64_img = msg['image']
        pil_img = utils.base64_to_image(b64_img)
        w, h = pil_img.size
        pil_img_big = pil_img.resize((w * 4, h * 4))
        answer = msg['answer']

        bboxes = utils.parse_bboxes_from_response(answer)
        if bboxes:
            result_image = pil_img_big
            if draw_type == "" or draw_type == "bboxes":
                print(f"Drawing '{filename}' with bboxes...")
                result_image = utils.draw_bboxes_on_image(pil_img_big, bboxes)
            elif draw_type == "mosaic":
                print(f"Drawing '{filename}' with mosaic...")
                result_image = utils.draw_mosaic_on_image(pil_img_big, bboxes)
            else:
                print(f"Unknown draw_type '{draw_type}', drawing '{filename}' with bboxes...")
                result_image = utils.draw_bboxes_on_image(pil_img_big, bboxes)

            cos.write_images([utils.ImageFile(filename, result_image)])
        else:
            print(f"No valid bounding boxes found with the image '{filename}'")
        
if __name__ == "__main__":
    app()
