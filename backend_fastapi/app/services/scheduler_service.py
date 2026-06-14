# app/services/scheduler_service.py
from datetime import date, datetime, timedelta
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session
from ..database import SessionLocal
from .petpooja_service import sync_all_active_outlets_by_fetch_date

scheduler = AsyncIOScheduler(timezone="Asia/Kolkata")

VERIFICATION_WINDOW_HOURS = 24


async def run_sync_job():
    """Daily Petpooja deep sync."""
    db: Session = SessionLocal()
    try:
        fetch_for_date = date.today()
        print(f"[AUTO SYNC] Starting Deep Sync for: {fetch_for_date}")
        result = await sync_all_active_outlets_by_fetch_date(
            db=db, fetch_for_date=fetch_for_date, force_refresh=True
        )
        print(f"[AUTO SYNC] Completed | Outlets Synced={result['outlets_synced']}")
    except Exception as e:
        print(f"[AUTO SYNC] Failed | Error: {e}")
    finally:
        db.close()


async def auto_close_expired_tickets():
    """Close RESOLVED maintenance tickets older than the 24h verification window."""
    from ..models.maintenance import MaintenanceIssue
    from ..api.routes.events import notify_clients

    db: Session = SessionLocal()
    try:
        threshold = datetime.utcnow() - timedelta(hours=VERIFICATION_WINDOW_HOURS)
        expired = db.query(MaintenanceIssue).filter(
            MaintenanceIssue.status == "RESOLVED",
            MaintenanceIssue.resolved_at <= threshold,
        ).all()

        for ticket in expired:
            ticket.status = "CLOSED"
            ticket.closed_at = datetime.utcnow()
            print(f"[AUTO_CLOSE] Ticket #{ticket.id} closed after {VERIFICATION_WINDOW_HOURS}h window.")

        if expired:
            db.commit()
            for ticket in expired:
                try:
                    await notify_clients({
                        "type": "maintenance_update",
                        "court_id": ticket.court_id,
                        "issue_id": ticket.id,
                        "status": "CLOSED",
                    })
                except Exception:
                    pass
    except Exception as e:
        db.rollback()
        print(f"[AUTO_CLOSE] Error: {e}")
    finally:
        db.close()


def start_scheduler():
    if scheduler.running:
        return

    scheduler.add_job(
        run_sync_job,
        trigger="cron", hour=3, minute=0,
        id="daily_deep_sync", replace_existing=True,
        max_instances=1, coalesce=True,
    )

    # ✅ Hourly maintenance auto-close sweep
    scheduler.add_job(
        auto_close_expired_tickets,
        trigger="cron", minute=0,
        id="maintenance_auto_close", replace_existing=True,
        max_instances=1, coalesce=True,
    )

    scheduler.start()
    print("[SCHEDULER] Started | Deep Sync 3:00 AM | Auto-close hourly")


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
        print("[SCHEDULER] Stopped")
