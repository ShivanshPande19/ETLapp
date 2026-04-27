#!/usr/bin/env python3
# generate_qr.py
# Run from backend_fastapi/ folder:
#   pip install qrcode[pil]
#   python generate_qr.py
#
# ⚠️  Edit BASE_URL to your server IP before running.
#     For production, change to your Railway/Render URL.

import qrcode
from pathlib import Path

BASE_URL = "http://172.20.10.3:8000"   # ← your Mac IP while developing
                                         # production: "https://your-app.railway.app"
OUT_DIR  = Path("qr_codes")
OUT_DIR.mkdir(exist_ok=True)

for court_id in [1, 2, 3]:
    url = f"{BASE_URL}/c/{court_id}"
    qr  = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_H,  # high error correction
        box_size=10,
        border=4,
    )
    qr.add_data(url)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    out = OUT_DIR / f"court_{court_id}_complaint_qr.png"
    img.save(str(out))
    print(f"  Court {court_id} QR  →  {out}")
    print(f"           URL: {url}")
    print()

print(f"Done — 3 QR PNGs saved to ./{OUT_DIR}/")
print("Print them, laminate them, and place in each court.")
