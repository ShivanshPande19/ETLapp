# app/services/notice_service.py
"""Create in-app notices and push a live SSE refresh ping.

Kept tiny and dependency-light so both the staff (shift change) and attendance
(early logout) flows can reuse it.
"""

from typing import Optional

from sqlalchemy.orm import Session

from ..models.notice import Notice
from ..api.routes.events import fire_notify


def create_notice(
    db: Session,
    *,
    audience: str,            # "manager" | "staff"
    type: str,                # "early_logout" | "shift_changed" | ...
    title: str,
    body: Optional[str] = None,
    court_id: Optional[int] = None,
    staff_id: Optional[int] = None,            # subject (who it's about)
    recipient_staff_id: Optional[int] = None,  # for audience="staff"
) -> Notice:
    notice = Notice(
        audience=audience,
        type=type,
        title=title,
        body=body,
        court_id=court_id,
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
            "audience": audience,
            "recipient_staff_id": recipient_staff_id,
        }
    )
    return notice
