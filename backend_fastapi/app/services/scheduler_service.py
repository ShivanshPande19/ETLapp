from datetime import date
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session

from ..database import SessionLocal
from .petpooja_service import sync_all_active_outlets_by_fetch_date

scheduler = AsyncIOScheduler(timezone="Asia/Kolkata")

async def run_daily_sales_sync():
    db: Session = SessionLocal()
    try:
        # Jis din job chalegi (e.g. 17th May at 2:20 AM)
        fetch_for_date = date.today()

        print(f"[AUTO SYNC] Started | fetch_for_date (API date) = {fetch_for_date}")

        result = await sync_all_active_outlets_by_fetch_date(
            db=db,
            fetch_for_date=fetch_for_date,
            force_refresh=True,  # Daily job mein humesha naya data override karna hai
        )

        print(
            f"[AUTO SYNC] Completed | "
            f"API Date={result['petpooja_api_date']} | "
            f"DB Business Date={result['business_date']} | "
            f"Outlets Synced={result['outlets_synced']}"
        )
    except Exception as e:
        print(f"[AUTO SYNC] Failed | error={e}")
    finally:
        db.close()


def start_scheduler():
    if scheduler.running:
        return

    scheduler.add_job(
        run_daily_sales_sync,
        trigger="cron",
        hour=1,        # 1 AM
        minute=55,     # 35 Minutes (1:35 AM)
        id="daily_petpooja_sales_sync",
        replace_existing=True,
        max_instances=1,
        coalesce=True,
    )

    scheduler.start()
    print("[AUTO SYNC] Scheduler started | Daily at 01:35 AM Asia/Kolkata")


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
        print("[AUTO SYNC] Scheduler stopped")