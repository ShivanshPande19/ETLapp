# app/services/notice_service.py
"""Create in-app notices, ping SSE for a live refresh, and push via FCM.

Kept tiny and dependency-light so both the staff (shift change) and attendance
(early logout) flows can reuse it.

This is the ONE choke point for user-facing notifications. Every notice created
here gets, in order:
  1. a persisted `Notice` row  (survives app restarts, shows in the inbox)
  2. an SSE ping               (instant refresh while the app is open)
  3. an FCM push               (reaches the user when the app is closed)

Targeting for (3) is resolved by services/push_targeting.py from the notice's
own audience/outlet_id/recipient_staff_id — the same rules
api/routes/notices.py::_scoped_query uses for reads, so a user can always open
what they were pushed.
"""

import logging
from typing import Optional

from sqlalchemy.orm import Session

from ..models.notice import Notice
from ..api.routes.events import fire_notify
from . import fcm_service
from .push_targeting import resolve_notice_targets

# Keep in sync with the Android channel created in the Flutter app
# (core/services/push_service.dart).
_ANDROID_CHANNEL_ID = "etl_default"


logger = logging.getLogger("notice")


def _unread_badge_for(db: Session, notice: Notice) -> int:
    """Recipient's TOTAL unread count in this notice's scope (mirrors
    api/routes/notices.py::_scoped_query). Sent as the app-icon badge so it
    reflects reality instead of the old hardcoded 1."""
    q = db.query(Notice).filter(Notice.is_read == False)  # noqa: E712
    if notice.audience == "staff":
        return q.filter(
            Notice.audience == "staff",
            Notice.recipient_staff_id == notice.recipient_staff_id,
        ).count()
    if notice.outlet_id is not None:
        return q.filter(
            Notice.audience == "manager",
            Notice.outlet_id == notice.outlet_id,
        ).count()
    return q.filter(
        Notice.audience == "manager",
        Notice.outlet_id.is_(None),
    ).count()


def _dispatch_push(db: Session, notice: Notice) -> None:
    """Resolve recipients and hand them to FCM. Never raises.

    Targets are resolved SYNCHRONOUSLY, on the caller's still-open session,
    before anything is scheduled on the event loop. The async send then only
    carries a plain list of strings. Doing it the other way round would mean
    touching a Session from another thread after the request had ended.
    """
    try:
        tokens = resolve_notice_targets(db, notice)
        if not tokens:
            return

        badge = _unread_badge_for(db, notice)

        data = {
            "type": notice.type,
            "notice_id": notice.id,
            "audience": notice.audience,
            "court_id": notice.court_id,
            "outlet_id": notice.outlet_id,
            # Consumed by the Flutter tap handler to deep-link into the app.
            "route": "/notices",
        }

        def _factory():
            return _send_and_prune(
                tokens,
                title=notice.title,
                body=notice.body,
                data=data,
                badge=badge,
            )

        fcm_service.fire_push(_factory)
    except Exception as e:  # noqa: BLE001 — a push must never break the caller
        logger.error("dispatch failed for notice#%s: %s", getattr(notice, "id", "?"), e)


async def _send_and_prune(tokens, *, title, body, data, badge=None) -> None:
    """Send, then soft-disable any token FCM reported as permanently dead.

    Uses its own short-lived session: by the time this runs the request that
    created the notice has already returned and its session is closed.
    """
    sent, dead = await fcm_service.send_push(
        tokens,
        title=title,
        body=body,
        data=data,
        android_channel_id=_ANDROID_CHANNEL_ID,
        badge=badge,
    )

    if not dead:
        return

    from ..database import SessionLocal
    from .push_targeting import deactivate_tokens

    db = SessionLocal()
    try:
        n = deactivate_tokens(db, dead)
        db.commit()
        logger.info("disabled %s dead token(s)", n)
    except Exception as e:  # noqa: BLE001
        db.rollback()
        logger.warning("could not disable dead tokens: %s", e)
    finally:
        db.close()


def create_notice(
    db: Session,
    *,
    audience: str,            # "manager" | "staff"
    type: str,                # "early_logout" | "shift_changed" | ...
    title: str,
    body: Optional[str] = None,
    court_id: Optional[int] = None,
    outlet_id: Optional[int] = None,           # set => belongs to an outlet manager
    staff_id: Optional[int] = None,            # subject (who it's about)
    recipient_staff_id: Optional[int] = None,  # for audience="staff"
    push: bool = True,                         # set False for low-value/noisy notices
) -> Notice:
    notice = Notice(
        audience=audience,
        type=type,
        title=title,
        body=body,
        court_id=court_id,
        outlet_id=outlet_id,
        staff_id=staff_id,
        recipient_staff_id=recipient_staff_id,
        is_read=False,
    )
    db.add(notice)
    db.commit()
    db.refresh(notice)

    # Live refresh: route to the court channel (+ managers on court_id 0).
    # Clients re-fetch their own notices; server filters by role/recipient.
    fire_notify(
        {
            "type": "notice_update",
            "court_id": court_id or 0,
            "outlet_id": outlet_id,
            "audience": audience,
            "recipient_staff_id": recipient_staff_id,
        }
    )

    # Background push — reaches the device even when the app is closed.
    if push:
        _dispatch_push(db, notice)

    return notice
