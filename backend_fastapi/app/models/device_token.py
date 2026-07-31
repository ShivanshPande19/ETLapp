# app/models/device_token.py
"""FCM device registration tokens.

WHY THIS TABLE LOOKS THE WAY IT DOES
────────────────────────────────────
1. `fcm_token` is UNIQUE. An FCM registration token identifies the app
   INSTALLATION, not the person. When user A signs out and user B signs in on
   the same phone, FCM hands back the SAME token. If A's row survived, B's
   device would start receiving A's notifications — a cross-tenant leak on a
   shared device. Registering a token therefore TRANSFERS ownership to the new
   user (see api/routes/devices.py::register_device).

2. There is deliberately NO ForeignKey on `user_id`. Identity lives in two
   separate tables (`managers` and `staff`), so the real identity is the
   composite (`user_type`, `user_id`). `manager.id == 1` and `staff.id == 1`
   are two different people.

3. `role`, `court_id` and `outlet_id` are DIAGNOSTIC / DEBUG ONLY.
   *** NEVER TARGET A PUSH USING THESE COLUMNS. ***
   They are a snapshot taken at registration time and go stale the moment a
   manager is moved to another outlet or a staff member is reassigned to
   another court (`PATCH /staff/{id}/court`). Targeting always JOINs live
   against `managers` / `staff` — see services/push_targeting.py.
"""

from datetime import datetime

from sqlalchemy import Column, Integer, String, Boolean, DateTime, Index
from sqlalchemy.sql import func

from ..database import Base


class DeviceToken(Base):
    __tablename__ = "device_tokens"

    id = Column(Integer, primary_key=True, index=True)

    # Composite identity — mirrors the "utype" pattern already used by the
    # reset-password token in api/routes/auth.py.
    user_type = Column(String, nullable=False, index=True)   # "manager" | "staff"
    user_id = Column(Integer, nullable=False, index=True)    # managers.id OR staff.id

    # JWT subject. Handy for debugging and for log lines that must not leak ids.
    email = Column(String, nullable=True, index=True)

    # ── Diagnostic snapshot. NOT for targeting. See module docstring. ─────────
    role = Column(String, nullable=True)
    court_id = Column(Integer, nullable=True)
    outlet_id = Column(Integer, nullable=True)

    # The FCM registration token. Unique — see point 1 above.
    fcm_token = Column(String, nullable=False, unique=True, index=True)

    platform = Column(String, nullable=True)      # "android" | "ios" | "web"
    app_version = Column(String, nullable=True)

    # Soft-disabled when the user logs out, is deactivated, or FCM reports the
    # token as UNREGISTERED. Kept (not deleted) for audit.
    is_active = Column(Boolean, nullable=False, default=True, index=True)

    created_at = Column(DateTime, server_default=func.now())
    last_seen_at = Column(DateTime, nullable=True, default=datetime.utcnow)

    __table_args__ = (
        # The hot path: "give me every live token for this exact user".
        Index("ix_device_tokens_owner", "user_type", "user_id", "is_active"),
    )

    def __repr__(self) -> str:  # pragma: no cover - debug helper
        return (
            f"<DeviceToken {self.user_type}:{self.user_id} "
            f"{self.platform} active={self.is_active}>"
        )
