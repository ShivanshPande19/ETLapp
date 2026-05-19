# seed_outlets.py  — ek baar chalao
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app.models.sale import Outlet, DailySaleCache

Base.metadata.create_all(bind=engine)

db = SessionLocal()

# Pehle check karo ki already exist toh nahi karta
if not db.query(Outlet).filter_by(rest_id="yk4ou3en").first():
    db.add(Outlet(
        court_id    = 1,
        court_name  = "Central 50",
        vendor_name = "I.M.M.MOMO ( Central 50 )",
        rest_id     = "yk4ou3en",
        is_active   = 1,
    ))
    db.commit()
    print("✅ Outlet seeded successfully")
else:
    print("ℹ️  Outlet already exists, skipping")

db.close()