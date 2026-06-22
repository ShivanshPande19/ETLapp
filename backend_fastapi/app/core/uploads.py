# app/core/uploads.py
"""Shared helper for persisting uploaded images to the configured UPLOAD_DIR.

On Railway, UPLOAD_DIR points at a mounted volume (e.g. /data/uploads) so the
files survive redeploys. The returned value is the URL path (served by the
``/uploads`` StaticFiles mount), NOT the on-disk path — so it resolves
correctly even when UPLOAD_DIR points at a volume outside the app directory.
"""

from __future__ import annotations

import os
import uuid

from fastapi import HTTPException, UploadFile

from app.core.config import settings

# ─── Image upload constraints ────────────────────────────────────────────────
_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}
_EXT_BY_TYPE = {
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
}
_MAX_PHOTO_BYTES = 8 * 1024 * 1024  # 8 MB (watermarked photos can be larger)


async def save_upload_image(photo: UploadFile, subdir: str, prefix: str = "img") -> str:
    """Validate (type + size) and persist an uploaded image under
    ``UPLOAD_DIR/<subdir>/``. Returns the public URL path
    ``uploads/<subdir>/<filename>``.
    """
    if photo.content_type not in _ALLOWED_IMAGE_TYPES:
        raise HTTPException(
            status_code=400,
            detail="Invalid image. Please upload a JPEG, PNG or WebP photo.",
        )

    data = await photo.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image upload.")
    if len(data) > _MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image too large (max 8 MB).")

    target_dir = os.path.join(settings.UPLOAD_DIR, subdir)
    os.makedirs(target_dir, exist_ok=True)

    ext = _EXT_BY_TYPE.get(photo.content_type, "jpg")
    filename = f"{prefix}_{uuid.uuid4()}.{ext}"
    with open(os.path.join(target_dir, filename), "wb") as buffer:
        buffer.write(data)

    return f"uploads/{subdir}/{filename}"
