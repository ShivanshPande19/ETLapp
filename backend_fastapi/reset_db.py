"""
reset_db.py - DANGER: wipes the ENTIRE database and recreates an empty schema,
then seeds ONLY the ETL manager login. Meant for a clean onboarding
end-to-end test.

It connects to whatever DATABASE_URL points at, so run it against the SAME DB
the app uses (e.g. the Railway Postgres public URL):

  cd backend_fastapi
  DATABASE_URL="postgresql://postgres:PASS@xxxx.proxy.rlwy.net:PORT/railway" python reset_db.py

A confirmation prompt protects against accidental wipes.

After running:
  1. Log in to the app as  manager@etl.com / 12345
  2. Settings -> Manage Courts -> "+ New Court"  (create e.g. "Central 50")
  3. Open  <PUBLIC_BASE_URL>/onboarding/apply  -> submit the outlet application
  4. In the app: court -> Outlets tab -> "Applications" -> Approve (rest_id)
  5. Trigger a sync to fetch sales:
       POST <PUBLIC_BASE_URL>/sales/sync?fetch_for_date=YYYY-MM-DD

To restore the full original demo data instead, run seed_master.py.
"""

import sys
import os

sys.path.insert(0, os.path.dirname(__file__))

from app.database import Base, engine, SessionLocal, DATABASE_URL

# Register ALL models so drop_all / create_all see every table.
from app.models import (  # noqa: F401
    manager,
    staff,
    sale,
    attendance,
    feedback,
    housekeeping,
    maintenance,
    vendor,
    onboarding,
)
from app.models.manager import Manager
from app.core.security import hash_password

CONFIRM = "RESET"


def main():
    shown = DATABASE_URL if len(DATABASE_URL) < 60 else DATABASE_URL[:60] + "..."
    print("Target DB :", shown)
    if DATABASE_URL.startswith("sqlite"):
        print("NOTE: This is a LOCAL SQLite DB (DATABASE_URL not set to Postgres).")

    ans = input(
        'This will DELETE ALL DATA in the above DB.\n'
        'Type "' + CONFIRM + '" to continue: '
    ).strip()
    if ans != CONFIRM:
        print("Aborted. Nothing changed.")
        return

    print("Dropping all tables...")
    Base.metadata.drop_all(bind=engine)
    print("Creating fresh empty schema...")
    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        mgr = Manager(
            name="Shivansh Pande",
            email="manager@etl.com",
            hashed_password=hash_password("12345"),
            role="etl_manager",
            outlet_id=None,
        )
        db.add(mgr)
        db.commit()
        print("")
        print("OK. Database reset complete.")
        print("Seeded ETL manager -> manager@etl.com / 12345")
        print("Courts, outlets, staff and sales are all EMPTY (ready for onboarding test).")
    finally:
        db.close()


if __name__ == "__main__":
    main()
