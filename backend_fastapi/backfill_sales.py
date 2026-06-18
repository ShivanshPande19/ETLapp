"""
backfill_sales.py - Petpooja sales data ko ek date range ke liye backfill karta hai.

Kya karta hai:
  - Saare ACTIVE outlets le aata hai
  - Range ki har date ka Petpooja se data fetch karta hai
  - 4 AM business-day buffer + per-bill dedup + DailySaleCache recalc
  - Idempotent: dubara chalao toh double count nahi hoga

4 AM BUFFER:
  Aakhri business-day ko poora capture karne ke liye uske agle din ki API date bhi
  fetch karni padti hai. Isliye END date ko aakhri business-day se +1 rakho.

Usage:
  python backfill_sales.py
  python backfill_sales.py 2026-06-11 2026-06-18
  python backfill_sales.py 2026-06-11 2026-06-18 --court COURT_UID
"""

import sys
import os
import asyncio
from datetime import date, timedelta

sys.path.insert(0, os.path.dirname(__file__))

from app.database import SessionLocal, engine, Base
from app.models.sale import Outlet, Court
from app.services.petpooja_service import sync_outlet_for_dates

# Default range: business 11-17 June, ek extra buffer din (18)
DEFAULT_API_START = date(2026, 6, 11)
DEFAULT_API_END = date(2026, 6, 18)


def parse_args():
    args = list(sys.argv[1:])
    court_uid = None

    if "--court" in args:
        idx = args.index("--court")
        if idx + 1 < len(args):
            court_uid = args[idx + 1]
            args = args[:idx] + args[idx + 2:]
        else:
            print("ERROR: court uid missing after --court")
            sys.exit(1)

    if len(args) >= 2:
        try:
            start = date.fromisoformat(args[0])
            end = date.fromisoformat(args[1])
        except ValueError:
            print("ERROR: dates must be YYYY-MM-DD format")
            sys.exit(1)
    else:
        start = DEFAULT_API_START
        end = DEFAULT_API_END

    if end < start:
        print("ERROR: end date cannot be before start date")
        sys.exit(1)

    return start, end, court_uid


def build_date_list(start, end):
    out = []
    curr = start
    while curr <= end:
        out.append(curr)
        curr = curr + timedelta(days=1)
    return out


async def run_backfill():
    start, end, court_uid = parse_args()
    api_dates = build_date_list(start, end)
    last_business_day = end - timedelta(days=1)

    print("Sales Backfill start")
    print("  API fetch range: " + str(start) + " to " + str(end))
    print("  Business dates : " + str(start) + " to " + str(last_business_day))
    if court_uid:
        print("  Court filter   : " + str(court_uid))
    print("")

    Base.metadata.create_all(bind=engine)

    db = SessionLocal()
    try:
        query = db.query(Outlet).filter(Outlet.is_active == 1)

        if court_uid:
            court = db.query(Court).filter(
                Court.court_uid == court_uid,
                Court.is_active == 1,
            ).first()
            if court is None:
                print("ERROR: court not found for uid " + str(court_uid))
                return
            query = query.filter(Outlet.court_id == court.id)

        outlets = query.all()
        if not outlets:
            print("ERROR: no active outlets found")
            return

        print(str(len(outlets)) + " active outlet(s) found")
        print("")

        grand_dates = set()
        for outlet in outlets:
            label = str(outlet.vendor_name) + " [rest_id=" + str(outlet.rest_id) + "]"
            print("Syncing " + label)
            try:
                affected = await sync_outlet_for_dates(
                    db=db,
                    outlet=outlet,
                    api_fetch_dates=api_dates,
                )
                grand_dates.update(affected)
                done = sorted(str(d) for d in affected)
                if done:
                    print("  OK updated: " + ", ".join(done))
                else:
                    print("  OK but no orders found")
            except Exception as exc:
                print("  ERROR: " + str(exc))
            print("")

        print("------------------------------------------")
        if grand_dates:
            all_dates = sorted(str(d) for d in grand_dates)
            print("DONE. " + str(len(all_dates)) + " business dates updated:")
            print("  " + ", ".join(all_dates))
        else:
            print("WARNING: nothing processed. Check Petpooja credentials and dates.")
    finally:
        db.close()


if __name__ == "__main__":
    asyncio.run(run_backfill())
