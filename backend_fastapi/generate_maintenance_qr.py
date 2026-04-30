"""
Run once to generate QR PNGs for every court+cart combination.
Each QR encodes the HTML form URL workers will see when they scan.

Usage:
    pip install qrcode[pil] pillow
    python generate_maintenance_qr.py
"""
import os
import qrcode
from PIL import Image, ImageDraw, ImageFont

# ── EDIT THIS: your machine's IP on the local WiFi ───────────────────────────
BASE_URL = "http://172.20.10.3:8000"      # same as your Flutter baseUrl
# ─────────────────────────────────────────────────────────────────────────────

COURTS = {1: "ETL Food Court", 2: "ETL Court 2", 3: "ETL Court 3"}
CARTS  = ["A", "B", "C"]

OUT_DIR = "maintenance_qr_codes"
os.makedirs(OUT_DIR, exist_ok=True)


def make_qr(court_id: int, court_name: str, cart_id: str):
    url = f"{BASE_URL}/m/{court_id}/{cart_id}"
    label = f"{court_name}  ·  Cart {cart_id}"

    qr = qrcode.QRCode(version=2, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)

    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    w, h = qr_img.size

    # Add label strip below QR
    strip_h = 60
    final = Image.new("RGB", (w, h + strip_h), "white")
    final.paste(qr_img, (0, 0))

    draw = ImageDraw.Draw(final)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
    except Exception:
        font = ImageFont.load_default()

    text_w = draw.textlength(label, font=font)
    draw.text(((w - text_w) / 2, h + 14), label, fill="black", font=font)

    filename = f"{OUT_DIR}/court{court_id}_cart{cart_id}.png"
    final.save(filename)
    print(f"✓  {filename}  →  {url}")


if __name__ == "__main__":
    print(f"Generating QR codes  (base: {BASE_URL})\n")
    for cid, cname in COURTS.items():
        for cart in CARTS:
            make_qr(cid, cname, cart)
    print(f"\nDone. {len(COURTS) * len(CARTS)} QR codes saved to '{OUT_DIR}/'")
