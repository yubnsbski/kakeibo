"""Image loading + preprocessing."""
from __future__ import annotations
import io
import cv2
import numpy as np
import pillow_heif
from PIL import Image

pillow_heif.register_heif_opener()


def load_image(data: bytes) -> np.ndarray:
    pil = Image.open(io.BytesIO(data))
    if pil.mode != "RGB":
        pil = pil.convert("RGB")
    rgb = np.array(pil)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    return bgr


def preprocess_for_ocr(bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.fastNlMeansDenoising(gray, h=10)
    binarized = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY,
        blockSize=31, C=10,
    )
    return binarized
