#!/usr/bin/env python3
import os
import qrcode
from pathlib import Path
import sys

# Make sure imports work properly
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal
from app.models.sale import Court
from app.core.config import settings

# Prefer the configured public URL (set PUBLIC_BASE_URL in .env) so a QR is
# never accidentally printed pointing at the wrong environment. Falls back to
# the production host, and an explicit CLI arg overrides everything:
#     python generate_qr.py https://staging.example.com
_DEFAULT_BASE_URL = "https://etl-backend-fresh-production.up.railway.app"
BASE_URL = (
    (sys.argv[1] if len(sys.argv) > 1 else "").strip()
    or (settings.PUBLIC_BASE_URL or "").strip()
    or _DEFAULT_BASE_URL
).rstrip("/")

OUT_DIR  = Path("qr_codes")
OUT_DIR.mkdir(exist_ok=True)

def generate_complaint_qrs():
    print(f"🚀 Generating Complaint QRs from DB (Base: {BASE_URL})\n")
    db = SessionLocal()
    
    try:
        courts = db.query(Court).filter(Court.is_active == 1).all()
        
        if not courts:
            print("❌ DB mein koi Court nahi mila!")
            return
            
        for court in courts:
            # Short path on purpose: fewer characters => lower QR density =>
            # more reliable scans off a printed standee. Served by the
            # `/c/{court_id}` redirect in app/main.py, which forwards to
            # /feedback/portal?court_id=... Never change this path — already
            # printed QRs cannot be updated.
            url = f"{BASE_URL}/c/{court.id}"
            qr  = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_H,  
                box_size=10,
                border=4,
            )
            qr.add_data(url)
            qr.make(fit=True)
            img = qr.make_image(fill_color="black", back_color="white")
            
            # File name clean karne ke liye spaces hata diye
            safe_name = court.name.replace(" ", "_")
            out = OUT_DIR / f"court_{court.id}_{safe_name}_complaint_qr.png"
            img.save(str(out))
            
            print(f"✅ Court '{court.name}' QR saved → {out}")
            
    finally:
        db.close()
        print(f"\n🎉 Done — Complaint QRs saved to ./{OUT_DIR}/")

if __name__ == "__main__":
    generate_complaint_qrs()