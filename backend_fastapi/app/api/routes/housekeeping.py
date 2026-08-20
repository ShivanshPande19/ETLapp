# app/api/routes/housekeeping.py

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from pydantic import BaseModel
from sqlalchemy import desc
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.housekeeping import HkTask, HkRecurring
from ...models.sale import Court
from ...core.uploads import save_upload_image
from ...services.housekeeping_config_service import get_court_config
from ..deps import CurrentUser, get_current_user
from .events import notify_clients

router = APIRouter()


def _upsert_insert(db: Session):
    """Return the dialect-correct INSERT construct. Postgres and SQLite both
    expose `.on_conflict_do_update(index_elements=..., set_=...)`, but the
    SQLite construct cannot be compiled by the Postgres dialect (and vice
    versa) — so we must pick the right one at runtime."""
    dialect = db.get_bind().dialect.name
    return pg_insert(HkTask) if dialect == "postgresql" else sqlite_insert(HkTask)


# ─── Pydantic schemas ─────────────────────────────────────────────────────────


class TaskSubmitItem(BaseModel):
    task_id:    str
    task_title: str
    is_done:    bool
    photo_url:  Optional[str] = None
    done_at:    Optional[str] = None


class ShiftSubmitRequest(BaseModel):
    court_id:     int
    shift:        str
    date:         str
    tasks:        List[TaskSubmitItem]
    submitted_by: Optional[int] = None


class RecurringTaskRequest(BaseModel):
    court_id:  int
    photo_url: Optional[str] = None
    done_by:   Optional[int] = None
    # Which recurring task (config key). If omitted, the court's first
    # weekly/monthly task is used (legacy: flagswash / fireaudit).
    task_id:   Optional[str] = None


# ─── SSE helper ───────────────────────────────────────────────────────────────

# Main event loop — main.py ke lifespan mein set hoga
_main_loop: asyncio.AbstractEventLoop | None = None


def _fire_notify(event: dict) -> None:
    """AnyIO worker thread se main event loop pe safely notify karo."""
    global _main_loop
    try:
        if _main_loop is None or not _main_loop.is_running():
            return
        asyncio.run_coroutine_threadsafe(notify_clients(event), _main_loop)
    except Exception as e:
        print(f"[SSE] notify failed: {e}")


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _shift_status(db: Session, court_id: int, shift_def: dict, date: str) -> dict:
    """Build a shift's status from its CONFIGURED tasks merged with completions.
    `shift_def` = {key, name, start_time, end_time, tasks:[{key,title,icon}]}."""
    shift_key = shift_def["key"]
    rows = (
        db.query(HkTask)
        .filter(
            HkTask.court_id == court_id,
            HkTask.shift    == shift_key,
            HkTask.date     == date,
        )
        .all()
    )
    by_task = {r.task_id: r for r in rows}

    cfg_tasks = shift_def.get("tasks", [])
    tasks = []
    for t in cfg_tasks:
        r = by_task.get(t["key"])
        tasks.append({
            "task_id":      t["key"],
            "task_title":   t.get("title") or (r.task_title if r else t["key"]),
            "icon":         t.get("icon"),
            "is_done":      bool(r.is_done) if r else False,
            "photo_url":    r.photo_url if r else None,
            "done_at":      r.done_at if r else None,
            "done_by_name": r.done_by_name if r else None,
        })

    done      = sum(1 for t in tasks if t["is_done"])
    total     = len(cfg_tasks)
    submitted = (done == total) and (total > 0)

    return {
        "shift":      shift_key,
        "shift_name": shift_def.get("name") or shift_key,
        "start_time": shift_def.get("start_time"),
        "end_time":   shift_def.get("end_time"),
        "total":      total,
        "done":       done,
        "submitted":  submitted,
        "tasks":      tasks,
    }


def _get_latest_recurring(
    db: Session, court_id: int, task_type: str, task_id: str
) -> Optional[HkRecurring]:
    return (
        db.query(HkRecurring)
        .filter(
            HkRecurring.court_id  == court_id,
            HkRecurring.task_type == task_type,
            HkRecurring.task_id   == task_id,
        )
        .order_by(desc(HkRecurring.done_at))
        .first()
    )


def _parse_done_at(row: Optional[HkRecurring]) -> Optional[datetime]:
    if row is None or not row.done_at:
        return None
    try:
        return datetime.fromisoformat(row.done_at)
    except (ValueError, TypeError):
        return None


def _recurring_status(
    db: Session,
    court_id: int,
    task_type: str,
    task_id: str,
    interval_days: int,
    title: Optional[str] = None,
    icon: Optional[str] = None,
) -> dict:
    row       = _get_latest_recurring(db, court_id, task_type, task_id)
    last_done = _parse_done_at(row)

    next_due   = (last_done + timedelta(days=interval_days)) if last_done else None
    now        = datetime.now()
    is_overdue = (next_due < now) if next_due else True

    return {
        "court_id":     court_id,
        "task_id":      task_id,
        "title":        title or task_id,
        "icon":         icon,
        "interval_days": interval_days,
        "last_done_at": last_done.isoformat() if last_done else None,
        "next_due_at":  next_due.isoformat()  if next_due  else None,
        "photo_url":    row.photo_url if row else None,
        "done_by_name": row.done_by_name if row else None,
        "is_overdue":   is_overdue,
    }


# ─── Tenancy guard ────────────────────────────────────────────────────────────


def _resolve_court_or_403(user: CurrentUser, requested: Optional[int]) -> int:
    """Resolve the court a housekeeping read/write may touch (P0-4 fix).

    Housekeeping is a court-level concept owned by ETL staff. The court MUST be
    derived from the caller's identity, never trusted from the client body/query
    — otherwise any authenticated user could submit/overwrite another court's
    checklist by changing `court_id` (IDOR).

      • ETL manager → may act on any court (admin/builder); uses `requested`.
      • ETL staff   → hard-locked to their OWN court; `requested` is ignored.
      • Outlet users→ 403 (outlets have no housekeeping).
    """
    if user.is_etl_manager:
        if requested is None:
            raise HTTPException(status_code=400, detail="court_id is required.")
        return requested
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id
    raise HTTPException(
        status_code=403, detail="Housekeeping is available to court staff only."
    )


# ─── Endpoints ────────────────────────────────────────────────────────────────


@router.post("/upload-photo", status_code=status.HTTP_201_CREATED)
async def upload_housekeeping_photo(
    photo: UploadFile = File(...),
    _user=Depends(get_current_user),
):
    """Persist a (watermarked) housekeeping proof photo on the Railway volume
    and return its public URL path. Replaces the old Cloudinary flow — the
    client compresses + watermarks (location + time) before uploading."""
    photo_url = await save_upload_image(photo, "housekeeping", "hk")
    return {"photo_url": photo_url}


@router.post("/submit", status_code=status.HTTP_200_OK)
def submit_shift(
    body: ShiftSubmitRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not body.tasks:
        raise HTTPException(
            status_code=422, detail="tasks list must not be empty"
        )

    # SECURITY (P0-4): lock the write to the caller's own court.
    body.court_id = _resolve_court_or_403(user, body.court_id)

    for task in body.tasks:
        # Record who completed it (from the JWT, never the client body).
        done_name = user.name if task.is_done else None
        stmt = (
            _upsert_insert(db)
            .values(
                court_id     = body.court_id,
                shift        = body.shift,
                date         = body.date,
                task_id      = task.task_id,
                task_title   = task.task_title,
                is_done      = task.is_done,
                photo_url    = task.photo_url,
                done_at      = task.done_at,
                done_by_name = done_name,
            )
            .on_conflict_do_update(
                index_elements=["court_id", "shift", "date", "task_id"],
                set_={
                    "is_done":      task.is_done,
                    "photo_url":    task.photo_url,
                    "done_at":      task.done_at,
                    "task_title":   task.task_title,
                    "done_by_name": done_name,
                },
            )
        )
        db.execute(stmt)

    db.commit()

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    body.shift,
        "date":     body.date,
    })

    return {"status": "ok", "submitted": len(body.tasks)}


@router.get("/status")
def get_status(
    date: Optional[str] = None,
    court_id: Optional[int] = None,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    target = date or datetime.now().strftime("%Y-%m-%d")

    # SECURITY (P0-4): ETL staff may only see THEIR court; the client fetches
    # without a court_id and filters locally, so forcing it here is transparent
    # to the app but blocks cross-court reads. ETL managers see all (or a
    # requested court); outlet users have no housekeeping.
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        court_id = user.court_id
    elif not user.is_etl_manager:
        raise HTTPException(
            status_code=403, detail="Housekeeping is available to court staff only."
        )

    # Config-driven: real active courts (optionally one), each with its own
    # configured shifts + tasks (legacy default is seeded if a court has none).
    court_q = db.query(Court).filter(Court.is_active == 1)
    if court_id is not None:
        court_q = court_q.filter(Court.id == court_id)
    court_rows = court_q.order_by(Court.id).all()

    courts = []
    weekly_tasks = []
    monthly_tasks = []
    for c in court_rows:
        cfg = get_court_config(db, c.id)
        courts.append({
            "court_id": c.id,
            "court_name": c.name,
            "date":     target,
            "shifts":   [_shift_status(db, c.id, sh, target) for sh in cfg["shifts"]],
        })
        for w in cfg["weekly"]:
            weekly_tasks.append(_recurring_status(
                db, c.id, "weekly", w["key"], w.get("interval_days") or 7,
                title=w.get("title"), icon=w.get("icon"),
            ))
        for m in cfg["monthly"]:
            monthly_tasks.append(_recurring_status(
                db, c.id, "monthly", m["key"], m.get("interval_days") or 30,
                title=m.get("title"), icon=m.get("icon"),
            ))

    return {
        "date":          target,
        "courts":        courts,
        "weekly_tasks":  weekly_tasks,
        "monthly_tasks": monthly_tasks,
    }


def _resolve_recurring_def(db: Session, court_id: int, scope: str, task_id: Optional[str]):
    """Find the config def for a weekly/monthly task (by key, or the court's
    first one as the legacy default). Returns the dict or None."""
    cfg = get_court_config(db, court_id)
    items = cfg["weekly"] if scope == "weekly" else cfg["monthly"]
    if not items:
        return None
    if task_id:
        for it in items:
            if it["key"] == task_id:
                return it
    return items[0]


@router.patch("/weekly", status_code=status.HTTP_200_OK)
def mark_weekly_done(
    body: RecurringTaskRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # SECURITY (P0-4): lock the write to the caller's own court.
    body.court_id = _resolve_court_or_403(user, body.court_id)

    item = _resolve_recurring_def(db, body.court_id, "weekly", body.task_id)
    if item is None:
        raise HTTPException(status_code=400, detail="No weekly task configured for this court.")
    task_key = item["key"]
    interval = item.get("interval_days") or 7

    row       = _get_latest_recurring(db, body.court_id, "weekly", task_key)
    last_done = _parse_done_at(row)
    now       = datetime.now()

    if last_done:
        next_due = last_done + timedelta(days=interval)
        if now < next_due:
            remaining = (next_due - now).days + (
                1 if (next_due - now).seconds > 0 else 0
            )
            raise HTTPException(
                status_code=400,
                detail={
                    "code":           "COOLDOWN_ACTIVE",
                    "message":        f"Task available again in {remaining} days.",
                    "remaining_days": remaining,
                    "next_due_at":    next_due.isoformat(),
                },
            )

    _add_recurring(db, body, "weekly", task_key, done_by_name=user.name)

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    "all",
        "date":     datetime.now().strftime("%Y-%m-%d"),
    })

    return {
        "status":   "ok",
        "task":     task_key,
        "court_id": body.court_id,
    }


@router.patch("/monthly", status_code=status.HTTP_200_OK)
def mark_monthly_done(
    body: RecurringTaskRequest,
    db:   Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    # SECURITY (P0-4): lock the write to the caller's own court.
    body.court_id = _resolve_court_or_403(user, body.court_id)

    item = _resolve_recurring_def(db, body.court_id, "monthly", body.task_id)
    if item is None:
        raise HTTPException(status_code=400, detail="No monthly task configured for this court.")
    task_key = item["key"]
    interval = item.get("interval_days") or 30

    row       = _get_latest_recurring(db, body.court_id, "monthly", task_key)
    last_done = _parse_done_at(row)
    now       = datetime.now()

    if last_done:
        next_due = last_done + timedelta(days=interval)
        if now < next_due:
            remaining = (next_due - now).days + (
                1 if (next_due - now).seconds > 0 else 0
            )
            raise HTTPException(
                status_code=400,
                detail={
                    "code":           "COOLDOWN_ACTIVE",
                    "message":        f"Task available again in {remaining} days.",
                    "remaining_days": remaining,
                    "next_due_at":    next_due.isoformat(),
                },
            )

    _add_recurring(db, body, "monthly", task_key, done_by_name=user.name)

    # ✅ SSE notify
    _fire_notify({
        "type":     "housekeeping_update",
        "court_id": body.court_id,
        "shift":    "all",
        "date":     datetime.now().strftime("%Y-%m-%d"),
    })

    return {
        "status":   "ok",
        "task":     task_key,
        "court_id": body.court_id,
    }


def _add_recurring(
    db: Session,
    body: RecurringTaskRequest,
    task_type: str,
    task_id: str,
    done_by_name: Optional[str] = None,
) -> None:
    row = HkRecurring(
        court_id     = body.court_id,
        task_type    = task_type,
        task_id      = task_id,
        done_at      = datetime.now().isoformat(),
        photo_url    = body.photo_url,
        done_by      = body.done_by,
        done_by_name = done_by_name,
    )
    db.add(row)
    db.commit()



# ─── Per-court checklist CONFIG (manager builder) ────────────────────────────
# Additive: these power the checklist builder. The legacy status/submit
# endpoints above are untouched until the staff/manager screens are wired to
# the config (next phase).

from ...services.housekeeping_config_service import (
    get_court_config,
    save_court_config,
    default_template,
)


class TaskDefIn(BaseModel):
    key: Optional[str] = None
    title: str
    icon: Optional[str] = None
    interval_days: Optional[int] = None


class ShiftConfigIn(BaseModel):
    key: Optional[str] = None
    name: str
    start_time: Optional[str] = None
    end_time: Optional[str] = None
    tasks: List[TaskDefIn] = []


class ChecklistConfigIn(BaseModel):
    shifts: List[ShiftConfigIn] = []
    weekly: List[TaskDefIn] = []
    monthly: List[TaskDefIn] = []


@router.get("/config")
def get_checklist_config(
    court_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Full checklist config for a court (seeds the legacy default if none).
    ETL managers may read any court's config (builder); ETL staff only their
    own court. Outlet users have no housekeeping (P0-4)."""
    if not user.is_etl_manager:
        if not user.is_etl_staff or user.court_id is None:
            raise HTTPException(
                status_code=403, detail="Housekeeping is available to court staff only."
            )
        if court_id != user.court_id:
            raise HTTPException(
                status_code=403, detail="You can only view your own court's checklist."
            )
    return get_court_config(db, court_id)


@router.get("/config/template")
def get_checklist_template(user: CurrentUser = Depends(get_current_user)):
    """A fresh editable template to pre-fill the builder for a NEW court."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    return default_template()


@router.put("/config")
def put_checklist_config(
    court_id: int,
    body: ChecklistConfigIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """ETL manager: replace a court's checklist config (shifts + tasks)."""
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")
    if not body.shifts:
        raise HTTPException(status_code=400, detail="At least one shift is required.")
    return save_court_config(db, court_id, body.model_dump())
