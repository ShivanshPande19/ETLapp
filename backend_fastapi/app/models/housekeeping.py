# app/models/housekeeping.py
# ─────────────────────────────────────────────────────────────────────────────
# SQLAlchemy ORM models for housekeeping tables.
# Imported in main.py so Base.metadata.create_all() picks them up on startup.
# ─────────────────────────────────────────────────────────────────────────────

from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
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
    created_at = Column(DateTime, server_default=func.now())
