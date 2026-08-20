# backend_fastapi/app/models/outlet_membership.py
#
# Multi-outlet ownership (Option A — junction table).
#
# A single person (one `managers` row = one login/email) can be linked to MANY
# outlets, across different courts, and one outlet can have MANY managers. This
# many-to-many relationship is what lets the same owner run e.g. "Coffee Vault"
# in both Central 50 and Bennett under a single login, and later lets an owner
# grant a limited co-manager access to a specific outlet.
#
# `membership_role` distinguishes:
#   • "owner"   → full access to the outlet AND may add/remove other managers
#                 for it. Created by the ETL onboarding approval.
#   • "manager" → limited: can view/operate the outlet (sales, feedback,
#                 maintenance, staff) but CANNOT manage access. Created when an
#                 owner assigns someone via the manage-access endpoint.
#
# The single legacy `Manager.outlet_id` column is retained as the manager's
# "primary" outlet (backward compatibility + a sensible default selection), but
# THIS table is the source of truth for what a manager can access.

from sqlalchemy import (
    Column,
    Integer,
    String,
    DateTime,
    ForeignKey,
    UniqueConstraint,
    Index,
    func,
)

from ..database import Base

# Valid membership roles.
MEMBERSHIP_OWNER = "owner"
MEMBERSHIP_MANAGER = "manager"


class OutletMembership(Base):
    __tablename__ = "outlet_memberships"

    id = Column(Integer, primary_key=True, autoincrement=True)
    manager_id = Column(
        Integer, ForeignKey("managers.id", ondelete="CASCADE"), nullable=False, index=True
    )
    outlet_id = Column(
        Integer, ForeignKey("outlets.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # "owner" | "manager"
    membership_role = Column(String, nullable=False, default=MEMBERSHIP_OWNER)
    created_at = Column(DateTime, server_default=func.now())

    __table_args__ = (
        # A person is linked to a given outlet at most once.
        UniqueConstraint("manager_id", "outlet_id", name="uq_outlet_membership"),
        Index("ix_outlet_membership_manager", "manager_id"),
        Index("ix_outlet_membership_outlet", "outlet_id"),
    )
