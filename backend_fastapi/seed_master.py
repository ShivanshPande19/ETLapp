import sys
import os
import asyncio
from datetime import date, timedelta

# Path set kar rahe hain
sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app.models.manager import Manager
from app.models.staff import Staff  # Naya import
from app.models.sale import Court, Outlet
from app.core.security import hash_password
from app.services.petpooja_service import sync_outlet_for_dates

async def main():
    print("🚀 Starting Master Seed Process...\n")
    
    # Nayi tables aur schema create karega
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    
    try:
        # 1. SUPER ADMIN (ETL MANAGER) CREATE KARNA
        manager_email = "manager@etl.com"
        manager = db.query(Manager).filter_by(email=manager_email).first()
        if not manager:
            manager = Manager(
                name="Shivansh Pande",
                email=manager_email,
                hashed_password=hash_password("12345"),
                role="etl_manager", # Role update kar diya
                outlet_id=None      # ETL Manager ka koi restricted outlet nahi hota
            )
            db.add(manager)
            db.commit()
            db.refresh(manager)
            print(f"✅ ETL Manager '{manager_email}' created!")
        
        # 2. COURT CREATE KARNA
        court = db.query(Court).filter_by(name="Central 50").first()
        if not court:
            court = Court(name="Central 50", manager_id=manager.id, is_active=1)
            db.add(court)
            db.commit()
            db.refresh(court)
            print("✅ Court 'Central 50' created!")

        # 3. OUTLET CREATE KARNA
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
            print("✅ Outlet 'I.M.M.MOMO' created!")

        # ==========================================================
        # 4. DUMMY ACCOUNTS FOR UI TESTING (Will be created via App later)
        # ==========================================================
        
        # A. Outlet Manager (Assigned to I.M.M.MOMO)
        out_mgr_email = "outletmgr@etl.com"
        if not db.query(Manager).filter_by(email=out_mgr_email).first():
            out_mgr = Manager(
                name="Momo Manager",
                email=out_mgr_email,
                hashed_password=hash_password("12345"),
                role="outlet_manager",
                outlet_id=outlet.id
            )
            db.add(out_mgr)
            print(f"✅ Outlet Manager '{out_mgr_email}' created!")

        # B. ETL Staff / Housekeeping (Assigned to Court)
        etl_staff_email = "housekeeping@etl.com"
        if not db.query(Staff).filter_by(email=etl_staff_email).first():
            etl_staff = Staff(
                name="Raju Housekeeping",
                email=etl_staff_email,
                hashed_password=hash_password("12345"),
                role="etl_staff",
                court_id=court.id,
                outlet_id=None
            )
            db.add(etl_staff)
            print(f"✅ ETL Staff '{etl_staff_email}' created!")

        # C. Outlet Staff (Assigned to I.M.M.MOMO)
        out_staff_email = "outletstaff@etl.com"
        if not db.query(Staff).filter_by(email=out_staff_email).first():
            out_staff = Staff(
                name="Chotu Staff",
                email=out_staff_email,
                hashed_password=hash_password("12345"),
                role="outlet_staff",
                court_id=None,
                outlet_id=outlet.id
            )
            db.add(out_staff)
            print(f"✅ Outlet Staff '{out_staff_email}' created!")
        
        # Save all dummy accounts
        db.commit()

        # ==========================================================
        # 5. PETPOOJA ASYNC FETCH (Dynamic Range)
        # ==========================================================
        print("\n🔄 Fetching Historical Data...")
        
        start_date = date(2026, 5, 14)
        end_date = date(2026, 5, 23)
        
        api_request_dates = []
        curr = start_date
        while curr <= end_date:
            api_request_dates.append(curr)
            curr += timedelta(days=1)
        
        print(f"Fetching for {len(api_request_dates)} days...")

        affected_dates = await sync_outlet_for_dates(
            db=db,
            outlet=outlet,
            api_fetch_dates=api_request_dates
        )
            
        if affected_dates:
            print(f"✅ Data processed successfully for business dates: {sorted(affected_dates)}")
        else:
            print("❌ No data processed.")

    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
        db.rollback() 
    finally:
        db.close()
        print("\n🎉 Master Seeding Completed Successfully!")

if __name__ == "__main__":
    asyncio.run(main())