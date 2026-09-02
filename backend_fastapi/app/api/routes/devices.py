# app/api/routes/devices.py
"""Device (FCM token) registration.

THE SHARED-DEVICE RULE
──────────────────────
An FCM registration token identifies the app INSTALLATION, not the person. When
one user signs out and another signs in on the same phone, FCM returns the SAME
token. So registering a token must TRANSFER it to the caller and drop the
previous owner's claim — otherwise the new user starts receiving the previous
user's notifications. On a food-court floor where staff share a device, that is
a real cross-tenant leak, not a theoretical one.

`fcm_token` is UNIQUE in the DB, which makes that transfer the only possible
outcome rather than something we have to remember to do.
"""

import logging
from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ...database import get_db
from ...models.device_token import DeviceToken
from ...schemas.device import (
    DeviceRegisterIn,
    DeviceRegisterOut,
    DeviceUnregisterIn,
    DeviceUnregisterOut,
)
from ...services import fcm_service
from ...services.push_targeting import deactivate_tokens_for_user
from ..deps import CurrentUser, get_current_user

logger = logging.getLogger("devices")

router = APIRouter()


@router.post("/register", response_model=DeviceRegisterOut)
def register_device(
    body: DeviceRegisterIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Bind this device's FCM token to the authenticated user.

    Idempotent: the app calls this on every login and on every token refresh.
    """
    existing = (
        db.query(DeviceToken)
        .filter(DeviceToken.fcm_token == body.fcm_token)
        .first()
    )

    now = datetime.utcnow()
    transferred = False

    if existing is not None:
        # Same token, possibly a different person than last time.
        transferred = not (
            existing.user_type == user.user_type and existing.user_id == user.id
        )
        if transferred:
            logger.info(
                "token transferred %s:%s -> %s:%s",
                existing.user_type, existing.user_id, user.user_type, user.id,
            )

        existing.user_type = user.user_type
        existing.user_id = user.id
        existing.email = user.email
        existing.role = user.role
        existing.court_id = user.court_id
        existing.outlet_id = user.outlet_id
        existing.platform = body.platform or existing.platform
        existing.app_version = body.app_version or existing.app_version
        existing.is_active = True
        existing.last_seen_at = now
    else:
        db.add(
            DeviceToken(
                user_type=user.user_type,
                user_id=user.id,
                email=user.email,
                role=user.role,
                court_id=user.court_id,
                outlet_id=user.outlet_id,
                fcm_token=body.fcm_token,
                platform=body.platform,
                app_version=body.app_version,
                is_active=True,
                last_seen_at=now,
            )
        )

    db.commit()

    return DeviceRegisterOut(
        status="ok",
        transferred=transferred,
        push_enabled=fcm_service.is_configured(),
    )


@router.post("/unregister", response_model=DeviceUnregisterOut)
def unregister_device(
    body: DeviceUnregisterIn,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Stop pushing to this device. Called on logout.

    Scoped to the caller: passing somebody else's token disables nothing, so
    this cannot be used to silence another user.
    """
    if body.fcm_token:
        disabled = (
            db.query(DeviceToken)
            .filter(
                DeviceToken.fcm_token == body.fcm_token,
                DeviceToken.user_type == user.user_type,
                DeviceToken.user_id == user.id,
            )
            .update({DeviceToken.is_active: False}, synchronize_session=False)
        )
        disabled = int(disabled or 0)
    else:
        # No token supplied — sign out of push on every device for this user.
        disabled = deactivate_tokens_for_user(
            db, user_type=user.user_type, user_id=user.id
        )

    db.commit()
    return DeviceUnregisterOut(status="ok", disabled=disabled)
