# app/services/scheduler_service.py
import asyncio
import json
import logging
from datetime import date, datetime, timedelta
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from sqlalchemy.orm import Session
from ..database import SessionLocal
from ..core.query_utils import now_ist
from .petpooja_service import sync_all_active_outlets_by_fetch_date

logger = logging.getLogger("scheduler")

scheduler = AsyncIOScheduler(timezone="Asia/Kolkata")

VERIFICATION_WINDOW_HOURS = 24

# ─── Maintenance reminder / escalation policy (ROLE SPLIT) ────────────────────
# A ticket is "open" (still needs work) in these statuses. RESOLVED/CLOSED stop
# reminders. The management tier for escalations = Azimuth Management + Crownest
# Head (per the locked notification matrix).
_MAINT_OPEN_STATUSES = ("RAISED", "ASSIGNED", "DISPUTED")
_MAINT_MGMT_TIER = ["azimuth_management", "crownest_head"]
_MAINT_REMINDER_GAP = timedelta(hours=6)
_MAINT_QUIET_START = 21   # 21:00 IST — reminders pause
_MAINT_QUIET_END = 9      # 09:00 IST — reminders resume


def _maint_targets(raw) -> list:
    """Parse the ticket's target_teams JSON defensively."""
    if not raw:
        return []
    try:
        v = json.loads(raw)
        return v if isinstance(v, list) else []
    except Exception:
        return []


async def run_sync_job():
    """Petpooja deep sync. Fetches a 3-day window ending on the IST date so the
    just-ended business day (incl. its post-midnight bills, which Petpooja files
    under the next calendar date) is captured completely."""
    db: Session = SessionLocal()
    try:
        # IST date, not the server's UTC date — at 3 AM IST the UTC date is
        # still "yesterday", which would shrink the window and drop the
        # after-midnight bills that belong to the business day being finalized.
        fetch_for_date = now_ist().date()
        logger.info("[AUTO SYNC] Starting Deep Sync for: %s", fetch_for_date)
        result = await sync_all_active_outlets_by_fetch_date(
            db=db, fetch_for_date=fetch_for_date, force_refresh=True
        )
        synced = result.get("outlets_synced", 0)
        failed = result.get("outlets_failed", 0)
        if failed:
            logger.warning("[AUTO SYNC] Completed WITH FAILURES | synced=%s failed=%s", synced, failed)
        else:
            logger.info("[AUTO SYNC] Completed | outlets=%s", synced)
    except Exception:
        logger.exception("[AUTO SYNC] Failed")
    finally:
        db.close()


async def auto_close_expired_tickets():
    """Close RESOLVED maintenance tickets older than the 24h verification window."""
    from ..models.maintenance import MaintenanceIssue
    from ..api.routes.events import notify_clients
    from .notice_service import create_notice

    db: Session = SessionLocal()
    try:
        threshold = datetime.utcnow() - timedelta(hours=VERIFICATION_WINDOW_HOURS)
        # Only the OUTLET-verification stage auto-closes: the ticket is RESOLVED,
        # the ops head has already verified (ops_verified_at set), and the owning
        # outlet hasn't confirmed within the window. The ops-verification stage
        # (ops_verified_at IS NULL) never auto-closes — the ops head must act.
        expired = db.query(MaintenanceIssue).filter(
            MaintenanceIssue.status == "RESOLVED",
            MaintenanceIssue.ops_verified_at.isnot(None),
            MaintenanceIssue.ops_verified_at <= threshold,
        ).all()

        for ticket in expired:
            ticket.status = "CLOSED"
            ticket.closed_at = datetime.utcnow()
            logger.info("[AUTO_CLOSE] Ticket #%s closed after %sh window.", ticket.id, VERIFICATION_WINDOW_HOURS)

        if expired:
            db.commit()
            for ticket in expired:
                try:
                    await notify_clients({
                        "type": "maintenance_update",
                        "court_id": ticket.court_id,
                        "outlet_id": ticket.outlet_id,
                        "issue_id": ticket.id,
                        "status": "CLOSED",
                    })
                except Exception:
                    pass

                # Trigger #11 — auto-closed without the outlet's verdict.
                # The outlet lost their say, so they get told; the ETL manager
                # gets it for the audit trail.
                try:
                    create_notice(
                        db,
                        audience="manager",
                        type="maintenance_auto_closed",
                        title="Ticket closed automatically",
                        body=(
                            f"Your {ticket.issue_type} ticket was closed after "
                            f"{VERIFICATION_WINDOW_HOURS}h without verification."
                        ),
                        outlet_id=ticket.outlet_id,
                    )
                    create_notice(
                        db,
                        audience="manager",
                        type="maintenance_auto_closed",
                        title="Ticket auto-closed (no verification)",
                        body=(
                            f"Ticket #{ticket.id} ({ticket.issue_type}) at "
                            f"{ticket.outlet_name or 'an outlet'} closed after "
                            f"{VERIFICATION_WINDOW_HOURS}h with no response."
                        ),
                        court_id=ticket.court_id,
                        outlet_id=None,
                    )
                except Exception as ne:
                    logger.warning("[AUTO_CLOSE] notice failed for #%s: %s", ticket.id, ne)
    except Exception as e:
        db.rollback()
        logger.exception("[AUTO_CLOSE] Error")
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
    from .push_targeting import manager_scope_for_staff

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
                # Shared helper, so this matches attendance.py and push targeting.
                mgr_court_id, mgr_outlet_id = manager_scope_for_staff(staff)
                if mgr_court_id is None and mgr_outlet_id is None:
                    mgr_court_id = rec.court_id
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
                    logger.warning("[AUTO_CLOSE_ATT] notice failed: %s", ne)
            logger.info("[AUTO_CLOSE_ATT] Auto-closed %s forgotten check-out(s).", len(closed))
    except Exception as e:
        db.rollback()
        logger.exception("[AUTO_CLOSE_ATT] Error")
    finally:
        db.close()


async def maintenance_reminders():
    """6-hourly nudge to the ticket's targeted maintenance team(s) while it is
    still OPEN. Runs hourly but only actually sends between 09:00–21:00 IST and
    at most once per 6h per ticket; stops the moment the ticket leaves the open
    statuses (resolved/closed)."""
    from ..models.maintenance import MaintenanceIssue
    from .notice_service import create_notice

    ist = now_ist()
    if not (_MAINT_QUIET_END <= ist.hour < _MAINT_QUIET_START):
        return  # quiet hours — never disturb overnight

    db: Session = SessionLocal()
    try:
        now = datetime.utcnow()
        rows = db.query(MaintenanceIssue).filter(
            MaintenanceIssue.status.in_(_MAINT_OPEN_STATUSES)
        ).all()
        sent = 0
        for issue in rows:
            targets = _maint_targets(issue.target_teams)
            if not targets:
                continue  # unrouted (triage) tickets have no assignee to remind
            last = issue.last_reminder_at
            if last is not None and (now - last) < _MAINT_REMINDER_GAP:
                continue
            try:
                issue.last_reminder_at = now
                create_notice(
                    db,
                    audience="role",
                    type="maintenance_reminder",
                    title=f"Reminder: ticket #{issue.id} still open",
                    body=(
                        f"{issue.issue_type} at "
                        f"{issue.outlet_name or issue.court_name or 'the site'}: "
                        f"{(issue.description or '')[:140]}"
                    ),
                    court_id=issue.court_id,
                    outlet_id=(issue.outlet_id or None),
                    target_roles=targets,
                )
                sent += 1
            except Exception as e:  # noqa: BLE001
                logger.warning("[MAINT REMINDER] #%s failed: %s", issue.id, e)
        if sent:
            db.commit()
            logger.info("[MAINT REMINDER] sent %s reminder(s)", sent)
    except Exception:
        db.rollback()
        logger.exception("[MAINT REMINDER] error")
    finally:
        db.close()


async def maintenance_escalations():
    """Escalate a still-OPEN ticket to the management tier (Azimuth Management +
    Crownest Head): after 2 days when Azimuth Maintenance is a target, or after
    4 days for a Crownest-Maintenance-only ticket. Each escalation fires once."""
    from ..models.maintenance import MaintenanceIssue
    from .notice_service import create_notice

    db: Session = SessionLocal()
    try:
        now = datetime.utcnow()
        rows = db.query(MaintenanceIssue).filter(
            MaintenanceIssue.status.in_(_MAINT_OPEN_STATUSES)
        ).all()

        def _escalate(issue, days: int):
            create_notice(
                db,
                audience="role",
                type="maintenance_escalation",
                title=f"Ticket #{issue.id} still open after {days} days",
                body=(
                    f"The {issue.issue_type} ticket at "
                    f"{issue.outlet_name or issue.court_name or 'the site'} is still "
                    f"unresolved after {days} days."
                ),
                court_id=issue.court_id,
                outlet_id=(issue.outlet_id or None),
                target_roles=_MAINT_MGMT_TIER,
            )

        fired = 0
        for issue in rows:
            targets = _maint_targets(issue.target_teams)
            if not targets:
                continue
            age = now - (issue.created_at or now)
            has_azimuth = "azimuth_maintenance" in targets
            try:
                if has_azimuth:
                    if age >= timedelta(days=2) and not issue.escalated_2d:
                        issue.escalated_2d = True
                        _escalate(issue, 2)
                        fired += 1
                else:  # Crownest-Maintenance-only ticket
                    if age >= timedelta(days=4) and not issue.escalated_4d:
                        issue.escalated_4d = True
                        _escalate(issue, 4)
                        fired += 1
            except Exception as e:  # noqa: BLE001
                logger.warning("[MAINT ESCALATION] #%s failed: %s", issue.id, e)
        if fired:
            db.commit()
            logger.info("[MAINT ESCALATION] fired %s", fired)
    except Exception:
        db.rollback()
        logger.exception("[MAINT ESCALATION] error")
    finally:
        db.close()


def start_scheduler():
    if scheduler.running:
        return

    scheduler.add_job(
        run_sync_job,
        trigger="cron", hour="3,13,19", minute=0,
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

    # ✅ Maintenance role-split: 6h reminders (09:00–21:00 IST, self-throttled)
    #    + 2d/4d escalations to the management tier. Both run hourly; the jobs
    #    themselves enforce the 6h gap / quiet hours / once-only escalation.
    scheduler.add_job(
        maintenance_reminders,
        trigger="cron", minute=15,
        id="maintenance_reminders", replace_existing=True,
        max_instances=1, coalesce=True,
    )
    scheduler.add_job(
        maintenance_escalations,
        trigger="cron", minute=20,
        id="maintenance_escalations", replace_existing=True,
        max_instances=1, coalesce=True,
    )

    scheduler.start()

    # Immediate one-off sync on boot/redeploy so fresh data doesn't wait until
    # the next cron tick. Runs on the already-running event loop (this is called
    # from the async lifespan), non-blocking. Today's (in-progress) sales are
    # never displayed — every sales range ends at "yesterday" — so this is safe.
    try:
        asyncio.get_running_loop().create_task(run_sync_job())
        logger.info("[SCHEDULER] Boot sync scheduled")
    except RuntimeError:
        # No running loop (e.g. called outside async context) — skip; the cron
        # jobs will still run on schedule.
        pass

    logger.info("[SCHEDULER] Started | Deep Sync 3AM/1PM/7PM IST | Auto-close hourly")


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown(wait=False)
        logger.info("[SCHEDULER] Stopped")
