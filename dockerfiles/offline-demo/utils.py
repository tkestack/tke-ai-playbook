from typing import List, Dict, Any, Tuple
import numpy
import ray
from ray.data import Dataset
from pyarrow import fs
from PIL import Image, ImageDraw
import matplotlib.colors as mcolors
import random
from io import BytesIO
import base64
import re
import json
from ray.data.datasource import FilenameProvider

class ImageFile:
    def __init__(self, filename, image):
        self.filename = filename
        self.image = image


class ImageFileNameProvider(FilenameProvider):
    def __init__(self, file_format: str):
        self.file_format = file_format

    def get_filename_for_row(
        self, row: Dict[str, Any], task_index: int, block_index: int, row_index: int
    ) -> str:
        if row["filename"] is not None:
            return f"{row['filename']}"
        return f"{task_index:06}_{block_index:06}_{row_index:06}.{self.file_format}"

class CosClient:
    def __init__(self, region: str, bucket: str, secret_id: str, secret_key: str):
        self.region = region
        self.bucket = bucket
        self.secret_id = secret_id
        self.secret_key = secret_key
        self.url = f"http://cos.{self.region}.myqcloud.com"
        self.s3 = fs.S3FileSystem(
            endpoint_override=self.url,
            access_key=self.secret_id,
            secret_key=self.secret_key,
            force_virtual_addressing=True,
        )

    def read_images(self) -> Dataset:
        return ray.data.read_images(
            f"s3://{self.bucket}/images/", filesystem=self.s3, include_paths=True
        )
    
    def write_images(self, images: List[ImageFile]):
        items = [
            {"filename": v.filename, "image": numpy.array(v.image)} for v in images
        ]
        ray.data.from_items(items).write_images(
            f"s3://{self.bucket}/outputs/",
            column="image",
            filesystem=self.s3,
            filename_provider=ImageFileNameProvider("png"),
        )
    

def image_to_base64(img: Image.Image, fmt='png') -> str:
    buf = BytesIO()
    img.save(buf, format=fmt)
    b64 = base64.b64encode(buf.getvalue()).decode('utf-8')
    return f'data:image/{fmt};base64,{b64}'

def base64_to_image(b64: str) -> Image.Image:
    b64_data = re.sub('^data:image/.+;base64,', '', b64)
    byte_data = base64.b64decode(b64_data)
    image_data = BytesIO(byte_data)
    return Image.open(image_data)

def parse_bboxes_from_response(response_text: str) -> List[Dict[str, Any]]:
    """
    Parses JSON-formatted bounding boxes from the model response.
    The expected format:
    [
        {"bbox_2d": [x1, y1, x2, y2], "label": "label_name"},
        {"bbox_2d": [x1, y1, x2, y2], "label": "label_name"},
        ...
    ]
    Returns a list of dictionaries: [{'box': (x1, y1, x2, y2), 'ref': 'label_name'}].
    """
    try:
        # Extract JSON content from response
        json_text = response_text.strip("```json").strip("```").strip()
        bboxes = json.loads(json_text)

        parsed_bboxes = []
        for item in bboxes:
            if "bbox_2d" in item and "label" in item:
                x1, y1, x2, y2 = item["bbox_2d"]
                parsed_bboxes.append({"box": (x1, y1, x2, y2), "ref": item["label"]})
        return parsed_bboxes
    except Exception as e:
        print("Failed to parse bounding boxes from response:", e)
        return []

def get_average_color(image: Image.Image):
    """Calculates the average color of an image."""
    img_array = numpy.array(image)
    # Calculate the mean along the height and width axes (axes 0 and 1)
    average_color_values = numpy.mean(img_array, axis=(0, 1))

    # Convert to integers (0-255 range)
    average_color_rgb = tuple(map(int, average_color_values))

    return average_color_rgb


def draw_mosaic_on_image(image: Image.Image, bboxes: List[Dict[str, Any]], block_size: int = 16) -> Image.Image | None:
    try:
        # Open the image
        image = image.convert("RGB")

        # Get image dimensions
        width, height = image.size

        xx1, xx2, yy1, yy2 = width, 0, height, 0

        for box_info in bboxes:
            # Extract bounding box and reference
            ref = box_info.get("ref", "")
            x1, y1, x2, y2 = box_info["box"]

            # Normalize coordinates to image dimensions if necessary
            x1, y1, x2, y2 = (
                int(x1),
                int(y1),
                int(x2),
                int(y2),
            )
            if x1 > x2:
                x1, x2 = x2, x1
            if y1 > y2:
                y1, y2 = y2, y1

            if xx1 > x1:
                xx1 = x1
            if xx2 < x2:
                xx2 = x2
            if yy1 > y1:
                yy1 = y1
            if yy2 < y2:
                yy2 = y2
            
        for i in range(yy1, yy2, block_size):
            for j in range(xx1, xx2, block_size):
                # Calculate the end coordinates for the current block
                block_x2 = min(j + block_size, xx2)
                block_y2 = min(i + block_size, yy2)

                # Get the average color of the block
                block = image.crop((j, i, block_x2, block_y2))
                avg_color = get_average_color(block)

                # Paste a solid color block back onto the image
                paste_block = Image.new('RGB', (block_x2 - j, block_y2 - i), avg_color)
                image.paste(paste_block, (j, i))

        return image
    except Exception as e:
        print("Failed to draw mosaic on image:", e)


def draw_bboxes_on_image(image: Image.Image, bboxes: List[Dict[str, Any]]) -> Image.Image | None:
    """
    Draw multiple bounding boxes on the image, label them with captions, and support random colors.
    """
    try:
        # Open the image
        image = image.convert("RGB")
        draw = ImageDraw.Draw(image)

        # Get image dimensions
        width, height = image.size

        # Initialize a random color generator
        color_choices = list(mcolors.TABLEAU_COLORS.keys())
        for box_info in bboxes:
            # Extract bounding box and reference
            ref = box_info.get("ref", "")
            x1, y1, x2, y2 = box_info["box"]

            # Normalize coordinates to image dimensions if necessary
            x1, y1, x2, y2 = (
                int(x1),
                int(y1),
                int(x2),
                int(y2),
            )

            # Choose a random color and convert to RGB
            color_name = random.choice(color_choices)
            color_rgb = tuple(
                int(255 * c) for c in mcolors.to_rgb(mcolors.TABLEAU_COLORS[color_name])
            )

            # Draw the bounding box
            draw.rectangle([x1, y1, x2, y2], outline=color_rgb, width=6)

            # Draw text caption above the bounding box
            caption = ref if ref else f"Object ({x1},{y1})"
            text_position = (x1, max(0, y1 - 15))  # Position above the bounding box
            draw.text(text_position, caption, fill=color_rgb)

        return image
    except Exception as e:
        print("Failed to draw bounding boxes on image:", e)

