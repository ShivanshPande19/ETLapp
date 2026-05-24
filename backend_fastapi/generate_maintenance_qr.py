import os
import qrcode
import sys
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal
from app.models.sale import Court, Outlet

BASE_URL = "https://etl-backend-fresh-production.up.railway.app"      
OUT_DIR = "maintenance_qr_codes"
os.makedirs(OUT_DIR, exist_ok=True)

def make_qr(court_id: int, court_name: str, outlet_id: int, outlet_name: str):
    # Route format according to your backend config
    url = f"{BASE_URL}/m/{court_id}/{outlet_id}"
    
    # Clean up names for display
    clean_vendor = outlet_name.split("(")[0].strip() # "I.M.M.MOMO ( Central 50 )" -> "I.M.M.MOMO"
    label = f"{court_name} · {clean_vendor}"

    qr = qrcode.QRCode(version=2, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=4)
    qr.add_data(url)
    qr.make(fit=True)

    qr_img = qr.make_image(fill_color="black", back_color="white").convert("RGB")
    w, h = qr_img.size

    # Add text label below QR
    strip_h = 60
    final = Image.new("RGB", (w, h + strip_h), "white")
    final.paste(qr_img, (0, 0))

    draw = ImageDraw.Draw(final)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
    except Exception:
        font = ImageFont.load_default()

    text_w = draw.textlength(label, font=font)
    draw.text(((w - text_w) / 2, h + 14), label, fill="black", font=font)

    # Clean filename
    safe_vendor_name = clean_vendor.replace(" ", "_").replace(".", "")
    filename = f"{OUT_DIR}/court{court_id}_{safe_vendor_name}_maintenance_qr.png"
    final.save(filename)
    print(f"✓  Generated: {filename}  →  {url}")

if __name__ == "__main__":
    print(f"🚀 Generating Clean Maintenance QRs from DB (Base: {BASE_URL})\n")
    
    db = SessionLocal()
    try:
        outlets = db.query(Outlet).filter(Outlet.is_active == 1).all()
        
        if not outlets:
            print("❌ DB mein koi Outlet nahi mila!")
        else:
            for outlet in outlets:
                court = db.query(Court).filter_by(id=outlet.court_id).first()
                court_name = court.name if court else "Central 50"
                make_qr(outlet.court_id, court_name, outlet.id, outlet.vendor_name)
    finally:
        db.close()
        print(f"\n🎉 Done. Maintenance QRs saved to '{OUT_DIR}/'")