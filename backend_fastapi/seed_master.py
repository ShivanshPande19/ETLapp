import sys
import os
import asyncio
from datetime import date, timedelta

# Path set kar rahe hain taaki imports perfectly kaam karein
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app.models.manager import Manager
from app.models.sale import Court, Outlet
from app.core.security import hash_password
from app.services.petpooja_service import sync_outlet_for_date

async def main():
    print("🚀 Starting Master Seed Process...\n")
    
    # 1. Database tables create karo
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    
    try:
        # ==========================================
        # 1. MANAGER CREATE KARNA (Perfect Hashing)
        # ==========================================
        manager_email = "manager@etl.com"
        manager = db.query(Manager).filter_by(email=manager_email).first()
        if not manager:
            manager = Manager(
                name="Shivansh Pande",
                email=manager_email,
                hashed_password=hash_password("12345"),
                role="manager",
                is_active=True
            )
            db.add(manager)
            db.commit()
            db.refresh(manager)
            print(f"✅ Manager '{manager_email}' created successfully!")
        else:
            print(f"ℹ️  Manager '{manager_email}' already exists.")

        # ==========================================
        # 2. COURT CREATE KARNA
        # ==========================================
        court = db.query(Court).filter_by(name="Central 50").first()
        if not court:
            court = Court(
                name="Central 50",
                manager_id=manager.id,
                is_active=1
            )
            db.add(court)
            db.commit()
            db.refresh(court)
            print("✅ Court 'Central 50' created successfully!")
        else:
            print("ℹ️  Court 'Central 50' already exists.")

        # ==========================================
        # 3. OUTLET CREATE KARNA
        # ==========================================
        rest_id = "yk4ou3en"
        outlet = db.query(Outlet).filter_by(rest_id=rest_id).first()
        if not outlet:
            outlet = Outlet(
                court_id=court.id,
                vendor_name="I.M.M.MOMO ( Central 50 )",
                rest_id=rest_id,
                is_active=1
            )
            db.add(outlet)
            db.commit()
            db.refresh(outlet)
            print("✅ Outlet 'I.M.M.MOMO' created successfully!")
        else:
            print("ℹ️  Outlet 'I.M.M.MOMO' already exists.")


        # ==========================================
        # 4. PETPOOJA ASYNC FETCH (16th to 20th May)
        # ==========================================
        print("\n🔄 Fetching REAL Data from PetPooja API...")
        
        # T+1 Logic: Business date 16th hai toh API date 17th jayegi
        api_request_dates = [
            date(2026, 5, 17), # Fetch karega 16th ka data
            date(2026, 5, 18), # Fetch karega 17th ka data
            date(2026, 5, 19), # Fetch karega 18th ka data
            date(2026, 5, 20), # Fetch karega 19th ka data
            date(2026, 5, 21)  # Fetch karega 20th ka data
        ]

        for api_date in api_request_dates:
            business_date = api_date - timedelta(days=1)
            
            # Using your EXACT native function from app.services.petpooja_service
            cache = await sync_outlet_for_date(
                db=db,
                outlet=outlet,
                target_business_date=business_date,
                api_fetch_date=api_date,
                force_refresh=True # Hamesha latest data overwite karega
            )
            
            if cache:
                print(f"✅ Data saved for Business Date: {business_date.strftime('%d-%b-%Y')} | Total Sales: ₹{cache.total_sales}")
            else:
                print(f"❌ Failed to fetch/save data for Business Date: {business_date.strftime('%d-%b-%Y')}")

    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
    finally:
        db.close()
        print("\n🎉 Master Seeding Completed Successfully!")

if __name__ == "__main__":
    asyncio.run(main())