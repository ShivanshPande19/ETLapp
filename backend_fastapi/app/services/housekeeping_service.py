from datetime import datetime, timedelta
from typing import List
from sqlalchemy.orm import Session

from ..models.housekeeping import (
    HousekeepingRecord, WeeklyTaskRecord, MonthlyTaskRecord, ShiftEnum
)
from ..schemas.housekeeping import (
    ShiftSubmitRequest, WeeklyTaskDoneRequest, MonthlyTaskDoneRequest,
    CourtDayStatus, ShiftStatus, TaskStatusItem,
    WeeklyTaskStatus, MonthlyTaskStatus, FullStatusResponse, SubmitResponse,
)

COURTS     = [1, 2, 3]
ALL_SHIFTS = ["morning", "day", "night"]

DEFAULT_TASKS = [
    {"task_id": "floor_clean",        "task_title": "Floor Cleaning"},
    {"task_id": "table_chair_clean",  "task_title": "Table & Chair Clean"},
    {"task_id": "bin_clean",          "task_title": "Bins Cleaning (outside)"},
    {"task_id": "tray_clean",         "task_title": "Tray Cleaning"},
    {"task_id": "bin_empty",          "task_title": "Garbage Bin Empty"},
    {"task_id": "pest_spray",         "task_title": "Pest Spray"},
]


# ── Staff: submit shift ───────────────────────────────────────────────────────

def submit_shift(db: Session, req: ShiftSubmitRequest) -> SubmitResponse:
    # Delete previous records for this slot so re-submission always wins
    db.query(HousekeepingRecord).filter(
        HousekeepingRecord.court_id == req.court_id,
        HousekeepingRecord.shift    == ShiftEnum(req.shift),
        HousekeepingRecord.date     == req.date,
    ).delete(synchronize_session=False)

    now = datetime.utcnow()
    for item in req.tasks:
        db.add(HousekeepingRecord(
            court_id     = req.court_id,
            shift        = ShiftEnum(req.shift),
            date         = req.date,
            task_id      = item.task_id,
            task_title   = item.task_title,
            is_done      = item.is_done,
            photo_url    = item.photo_url,
            done_at      = now if item.is_done else None,
            submitted_by = req.submitted_by,
            created_at   = now,
            updated_at   = now,
        ))
    db.commit()
    return SubmitResponse(
        success=True, message="Shift submitted successfully",
        court_id=req.court_id, shift=ShiftEnum(req.shift), date=req.date,
    )


# ── Staff: weekly task ────────────────────────────────────────────────────────

def mark_weekly_done(db: Session, req: WeeklyTaskDoneRequest) -> WeeklyTaskStatus:
    row = db.query(WeeklyTaskRecord).filter(
        WeeklyTaskRecord.court_id == req.court_id
    ).first()
    now = datetime.utcnow()
    if row:
        row.last_done_at = now
        row.photo_url    = req.photo_url
        row.done_by      = req.done_by
        row.updated_at   = now
    else:
        row = WeeklyTaskRecord(
            court_id=req.court_id, last_done_at=now,
            photo_url=req.photo_url, done_by=req.done_by, updated_at=now,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return _build_weekly_status(row.court_id, row)


# ── Staff: monthly task ───────────────────────────────────────────────────────

def mark_monthly_done(db: Session, req: MonthlyTaskDoneRequest) -> MonthlyTaskStatus:
    row = db.query(MonthlyTaskRecord).filter(
        MonthlyTaskRecord.court_id == req.court_id
    ).first()
    now = datetime.utcnow()
    if row:
        row.last_done_at = now
        row.photo_url    = req.photo_url
        row.done_by      = req.done_by
        row.updated_at   = now
    else:
        row = MonthlyTaskRecord(
            court_id=req.court_id, last_done_at=now,
            photo_url=req.photo_url, done_by=req.done_by, updated_at=now,
        )
        db.add(row)
    db.commit()
    db.refresh(row)
    return _build_monthly_status(row.court_id, row)


# ── Manager: full status ──────────────────────────────────────────────────────

def get_full_status(db: Session, date: str) -> FullStatusResponse:
    courts_status = [_build_court_status(db, c, date) for c in COURTS]
    weekly_status = [
        _build_weekly_status(c,
            db.query(WeeklyTaskRecord).filter(WeeklyTaskRecord.court_id == c).first())
        for c in COURTS
    ]
    monthly_status = [
        _build_monthly_status(c,
            db.query(MonthlyTaskRecord).filter(MonthlyTaskRecord.court_id == c).first())
        for c in COURTS
    ]
    return FullStatusResponse(
        date=date, courts=courts_status,
        weekly_tasks=weekly_status, monthly_tasks=monthly_status,
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _build_court_status(db: Session, court_id: int, date: str) -> CourtDayStatus:
    shifts = []
    for shift in ALL_SHIFTS:
        records: List[HousekeepingRecord] = db.query(HousekeepingRecord).filter(
            HousekeepingRecord.court_id == court_id,
            HousekeepingRecord.shift    == ShiftEnum(shift),
            HousekeepingRecord.date     == date,
        ).all()

        if records:
            task_items = [
                TaskStatusItem(
                    task_id=r.task_id, task_title=r.task_title,
                    is_done=r.is_done, photo_url=r.photo_url, done_at=r.done_at,
                )
                for r in records
            ]
        else:
            task_items = [
                TaskStatusItem(task_id=t["task_id"], task_title=t["task_title"],
                               is_done=False, photo_url=None, done_at=None)
                for t in DEFAULT_TASKS
            ]

        done_count = sum(1 for t in task_items if t.is_done)
        shifts.append(ShiftStatus(
            shift=ShiftEnum(shift), total=len(task_items),
            done=done_count, submitted=len(records) > 0, tasks=task_items,
        ))
    return CourtDayStatus(court_id=court_id, date=date, shifts=shifts)


def _build_weekly_status(court_id: int, row) -> WeeklyTaskStatus:
    if row and row.last_done_at:
        nxt = row.last_done_at + timedelta(days=7)
        return WeeklyTaskStatus(
            court_id=court_id, last_done_at=row.last_done_at,
            next_due_at=nxt, photo_url=row.photo_url,
            is_overdue=datetime.utcnow() > nxt,
        )
    return WeeklyTaskStatus(court_id=court_id, last_done_at=None,
                            next_due_at=None, photo_url=None, is_overdue=True)


def _build_monthly_status(court_id: int, row) -> MonthlyTaskStatus:
    if row and row.last_done_at:
        nxt = row.last_done_at + timedelta(days=30)
        return MonthlyTaskStatus(
            court_id=court_id, last_done_at=row.last_done_at,
            next_due_at=nxt, photo_url=row.photo_url,
            is_overdue=datetime.utcnow() > nxt,
        )
    return MonthlyTaskStatus(court_id=court_id, last_done_at=None,
                             next_due_at=None, photo_url=None, is_overdue=True)