# app/models/housekeeping.py
# ─────────────────────────────────────────────────────────────────────────────
# SQLAlchemy ORM models for housekeeping tables.
# Imported in main.py so Base.metadata.create_all() picks them up on startup.
# ─────────────────────────────────────────────────────────────────────────────

from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, func
from sqlalchemy.orm import declarative_mixin

from ..database import Base          # your existing Base from app/database.py


class HkTask(Base):
    """
    One row per (court_id, shift, date, task_id).
    UPSERT on re-submission — no duplicate rows.
    """
    __tablename__ = "hk_tasks"

    id           = Column(Integer, primary_key=True, autoincrement=True)
    court_id     = Column(Integer,  nullable=False, index=True)
    shift        = Column(String,   nullable=False)   # morning | day | night
    date         = Column(String,   nullable=False)   # YYYY-MM-DD
    task_id      = Column(String,   nullable=False)
    task_title   = Column(String,   nullable=True)
    is_done      = Column(Boolean,  nullable=False, default=False)
    photo_url    = Column(String,   nullable=True)
    done_at      = Column(String,   nullable=True)    # ISO-8601 from Flutter
    done_by_name = Column(String,   nullable=True)    # staff who completed it
    submitted_at = Column(DateTime, server_default=func.now())

    # Composite unique constraint — enforced at DB level
    from sqlalchemy import UniqueConstraint
    __table_args__ = (
        UniqueConstraint("court_id", "shift", "date", "task_id",
                         name="uq_hk_tasks_submission"),
    )


class HkRecurring(Base):
    """
    Audit trail for weekly (flags washing) and monthly (fire safety) tasks.
    Every completion adds a new row — the latest row per (court, type) is
    used to compute next_due_at / is_overdue.
    """
    __tablename__ = "hk_recurring"

    id         = Column(Integer,  primary_key=True, autoincrement=True)
    court_id   = Column(Integer,  nullable=False, index=True)
    task_type  = Column(String,   nullable=False)   # weekly | monthly
    task_id    = Column(String,   nullable=False)   # flagswash | fireaudit
    done_at    = Column(String,   nullable=False)   # ISO-8601
    photo_url  = Column(String,   nullable=True)
    done_by    = Column(Integer,  nullable=True)    # staff user id
    done_by_name = Column(String, nullable=True)    # staff who completed it
    created_at = Column(DateTime, server_default=func.now())



# ─────────────────────────────────────────────────────────────────────────────
# Per-court housekeeping CONFIG (the manager-built checklist).
# These define WHAT shifts/tasks exist for a court; the HkTask/HkRecurring
# tables above record completions against them (keyed by the stable `key`s).
# ─────────────────────────────────────────────────────────────────────────────


class HkShift(Base):
    """A configurable shift for a court (name + timings). `key` is stable and
    used as `HkTask.shift`, so renaming the display `name` never orphans past
    completions."""
    __tablename__ = "hk_shift"

    id         = Column(Integer, primary_key=True, autoincrement=True)
    court_id   = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=False, index=True)
    key        = Column(String, nullable=False)        # stable: 'morning' | 'shift_ab12cd'
    name       = Column(String, nullable=False)        # display: 'Morning'
    start_time = Column(String, nullable=True)         # "HH:MM" 24h
    end_time   = Column(String, nullable=True)
    sort_order = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=func.now())


class HkTaskDef(Base):
    """A configurable task. scope='daily' tasks belong to a shift (shift_key);
    scope='weekly'/'monthly' are court-level recurring tasks. `key` is stable
    and used as HkTask.task_id / HkRecurring.task_id."""
    __tablename__ = "hk_taskdef"

    id            = Column(Integer, primary_key=True, autoincrement=True)
    court_id      = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=False, index=True)
    scope         = Column(String, nullable=False)     # daily | weekly | monthly
    shift_key     = Column(String, nullable=True, index=True)  # set for scope='daily'
    key           = Column(String, nullable=False)     # stable: 'floorclean' | 'task_ab12cd'
    title         = Column(String, nullable=False)
    icon          = Column(String, nullable=True)      # icon name (Flutter maps it)
    interval_days = Column(Integer, nullable=True)     # weekly=7, monthly=30 (configurable)
    sort_order    = Column(Integer, nullable=False, default=0)
    created_at    = Column(DateTime, server_default=func.now())
