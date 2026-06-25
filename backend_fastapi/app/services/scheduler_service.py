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


async def auto_close_forgotten_attendance():
    """Auto-close attendance where staff forgot to check out.

    For every open record (checked in, never checked out) whose BUSINESS DAY
    has already rolled over, set the check-out to the scheduled shift end (or
    the business-day boundary if no shift), flag it auto_closed, and notify both
    the manager and the staff. Overnight-court aware via each court's cutoff.
    """
    from ..models.attendance import Attendance
    from ..models.staff import Staff
    from ..models.sale import Court
    from ..core.query_utils import (
        current_business_date,
        business_date_for,
        now_ist,
        to_ist,
        scheduled_shift_end_utc,
        business_day_end_utc,
    )
    from .notice_service import create_notice

    db: Session = SessionLocal()
    try:
        open_recs = db.query(Attendance).filter(
            Attendance.check_in_time.isnot(None),
            Attendance.check_out_time.is_(None),
        ).all()

        court_cutoffs: dict[int, int] = {}

        def cutoff_for(court_id):
            if not court_id:
                return 0
            if court_id not in court_cutoffs:
                c = db.query(Court).filter(Court.id == court_id).first()
                court_cutoffs[court_id] = (c.day_cutoff_hour or 0) if c else 0
            return court_cutoffs[court_id]

        closed = []
        for rec in open_recs:
            cutoff = cutoff_for(rec.court_id)
            biz = rec.business_date
            if biz is None and rec.check_in_time is not None:
                biz = business_date_for(to_ist(rec.check_in_time), cutoff)
            if biz is None:
                continue

            # Only close once the business day is fully over.
            if current_business_date(cutoff) <= biz:
                continue

            staff = db.query(Staff).filter(Staff.id == rec.staff_id).first()
            close_at = None
            if staff is not None:
                close_at = scheduled_shift_end_utc(biz, staff.shift_start, staff.shift_end)
            if close_at is None:
                close_at = business_day_end_utc(biz, cutoff)

            rec.check_out_time = close_at
            rec.auto_closed = True
            rec.check_out_address = "Auto-closed (no check-out)"
            closed.append((rec, staff, close_at))

        if closed:
            db.commit()
            for rec, staff, close_at in closed:
                name = staff.name if staff else "Staff"
                out_local = to_ist(close_at).strftime("%I:%M %p").lstrip("0")
                # Route to outlet manager (outlet staff) or court/ETL manager.
                if staff and staff.outlet_id and not staff.court_id:
                    mgr_court_id, mgr_outlet_id = None, staff.outlet_id
                else:
                    mgr_court_id, mgr_outlet_id = rec.court_id, None
                try:
                    create_notice(
                        db,
                        audience="manager",
                        type="missed_checkout",
                        title=f"{name} forgot to check out",
                        body=(
                            f"{name} didn't check out. The system auto-closed "
                            f"their shift at {out_local}."
                        ),
                        court_id=mgr_court_id,
                        outlet_id=mgr_outlet_id,
                        staff_id=rec.staff_id,
                    )
                    if staff is not None:
                        create_notice(
                            db,
                            audience="staff",
                            type="missed_checkout",
                            title="You forgot to check out",
                            body=(
                                f"Your shift was auto-closed at {out_local}. "
                                f"Please remember to check out next time."
                            ),
                            court_id=staff.court_id,
                            outlet_id=staff.outlet_id,
                            staff_id=rec.staff_id,
                            recipient_staff_id=rec.staff_id,
                        )
                except Exception as ne:
                    print(f"[AUTO_CLOSE_ATT] notice failed: {ne}")
            print(f"[AUTO_CLOSE_ATT] Auto-closed {len(closed)} forgotten check-out(s).")
    except Exception as e:
        db.rollback()
        print(f"[AUTO_CLOSE_ATT] Error: {e}")
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

    # ✅ Hourly attendance auto-close for forgotten check-outs
    scheduler.add_job(
        auto_close_forgotten_attendance,
        trigger="cron", minute=10,
        id="attendance_auto_close", replace_existing=True,
        max_instances=1, coalesce=True,
    )

    scheduler.start()
    print("[SCHEDULER] Started | Deep Sync 3:00 AM | Auto-close hourly")


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
        print("[SCHEDULER] Stopped")
