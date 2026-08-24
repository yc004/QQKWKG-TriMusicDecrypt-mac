from __future__ import annotations

import sys
import types
from typing import BinaryIO


def what(file: str | BinaryIO | None, h: bytes | None = None) -> str | None:
    """Small compatibility implementation for ncmdump on Python 3.13+."""
    if h is None:
        if file is None:
            return None
        if hasattr(file, "read"):
            h = file.read(32)  # type: ignore[union-attr]
        else:
            with open(file, "rb") as image_file:  # type: ignore[arg-type]
                h = image_file.read(32)
    if h.startswith(b"\xff\xd8\xff"):
        return "jpeg"
    if h.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if h.startswith((b"GIF87a", b"GIF89a")):
        return "gif"
    if h.startswith(b"BM"):
        return "bmp"
    if h.startswith((b"II*\x00", b"MM\x00*")):
        return "tiff"
    if len(h) >= 12 and h[:4] == b"RIFF" and h[8:12] == b"WEBP":
        return "webp"
    return None


def install() -> None:
    module = types.ModuleType("imghdr")
    module.what = what  # type: ignore[attr-defined]
    sys.modules.setdefault("imghdr", module)
