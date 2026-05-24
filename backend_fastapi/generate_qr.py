#!/usr/bin/env python3
import os
import qrcode
from pathlib import Path
import sys

# Make sure imports work properly
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal
from app.models.sale import Court

BASE_URL = "https://etl-backend-fresh-production.up.railway.app" 
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