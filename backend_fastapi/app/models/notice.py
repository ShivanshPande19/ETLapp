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

from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Index, Text
from sqlalchemy.sql import func

from ..database import Base


class Notice(Base):
    __tablename__ = "notices"

    id = Column(Integer, primary_key=True, index=True)

    # "manager" | "staff" | "role"
    #   "role" (ROLE SPLIT) targets every active account (manager OR staff)
    #   whose role is in `target_roles`, plus any named individual recipient
    #   (recipient_manager_id / recipient_staff_id). Used for the maintenance
    #   notification matrix (targeted teams, mentions, management-tier alerts).
    audience = Column(String, nullable=False, index=True)

    # Category, e.g. "early_logout" | "shift_changed"
    type = Column(String, nullable=False)

    # Court this notice belongs to (manager scoping / future per-court managers).
    court_id = Column(Integer, ForeignKey("courts.id", ondelete="CASCADE"), nullable=True, index=True)

    # Outlet this notice belongs to (set for outlet-manager notices so the
    # outlet manager sees their outlet's notices; null for court/ETL notices).
    outlet_id = Column(Integer, ForeignKey("outlets.id", ondelete="CASCADE"), nullable=True, index=True)

    # The staff this notice is ABOUT (subject) — e.g. who logged out early.
    staff_id = Column(Integer, ForeignKey("staff.id", ondelete="SET NULL"), nullable=True)

    # For audience="staff": the staff who should RECEIVE this notice.
    recipient_staff_id = Column(Integer, ForeignKey("staff.id", ondelete="CASCADE"), nullable=True, index=True)

    # For audience="role": JSON list of role keys to deliver to, e.g.
    # ["azimuth_maintenance"] or ["azimuth_management","crownest_head"].
    target_roles = Column(Text, nullable=True)

    # For audience="role": optionally also deliver to ONE named manager (an
    # individual "mention"). Parallel to recipient_staff_id for staff mentions.
    recipient_manager_id = Column(Integer, ForeignKey("managers.id", ondelete="CASCADE"), nullable=True, index=True)

    title = Column(String, nullable=False)
    body = Column(String, nullable=True)

    is_read = Column(Boolean, nullable=False, default=False, index=True)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        Index("ix_notices_audience_read", "audience", "is_read"),
    )
