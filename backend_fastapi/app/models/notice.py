# app/models/notice.py
"""In-app notices / notifications.

Two audiences:
  • "manager" — e.g. "X logged out early" (shown in Settings → Notices with
    read/unread). Scoped by `court_id` so that when per-court manager
    assignment is added later, filtering is a one-line query change.
  • "staff"   — e.g. "Your shift timings changed" / "You logged out early",
    delivered to a specific staff member (`recipient_staff_id`).
"""

from datetime import datetime

from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Index
from sqlalchemy.sql import func

from ..database import Base


class Notice(Base):
    __tablename__ = "notices"

    id = Column(Integer, primary_key=True, index=True)

    # "manager" | "staff"
    audience = Column(String, nullable=False, index=True)

    # Category, e.g. "early_logout" | "shift_changed"
    type = Column(String, nullable=False)

    # Court this notice belongs to (manager scoping / future per-court managers).
    court_id = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=True, index=True)

    # The staff this notice is ABOUT (subject) — e.g. who logged out early.
    staff_id = Column(Integer, ForeignKey("staff.id", ondelete="SET NULL"), nullable=True)

    # For audience="staff": the staff who should RECEIVE this notice.
    recipient_staff_id = Column(Integer, ForeignKey("staff.id", ondelete="CASCADE"), nullable=True, index=True)

    title = Column(String, nullable=False)
    body = Column(String, nullable=True)

    is_read = Column(Boolean, nullable=False, default=False, index=True)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        Index("ix_notices_audience_read", "audience", "is_read"),
    )
