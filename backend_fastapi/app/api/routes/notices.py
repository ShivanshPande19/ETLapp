# app/api/routes/notices.py
from datetime import datetime, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func
from sqlalchemy.orm import Session

# created_at is stored as naive UTC. Notices are grouped/filtered by the IST
# calendar day the user experienced them on. IST has no DST, so a fixed +5:30
# offset is exact.
_IST_OFFSET = timedelta(hours=5, minutes=30)


def _ist_day_utc_bounds(date_str: str):
    """[start, end) UTC datetimes covering the given YYYY-MM-DD IST day."""
    day = datetime.strptime(date_str, "%Y-%m-%d")  # naive = IST midnight
    start_utc = day - _IST_OFFSET
    end_utc = day + timedelta(days=1) - _IST_OFFSET
    return start_utc, end_utc

from ...database import get_db
from ...models.notice import Notice
from ...schemas.notice import NoticeListResponse, NoticeOut, UnreadCountResponse
from ..deps import get_current_user, CurrentUser

router = APIRouter()


def _scoped_query(db: Session, user: CurrentUser):
    """Notices visible to the current user.

    • ETL manager   → court-level manager notices (outlet_id IS NULL).
    • Outlet manager → manager notices for THEIR outlet (outlet_id == their outlet).
    • ETL/outlet staff → their own audience="staff" notices.
    • Others → nothing.
    """
    if user.is_etl_manager:
        return db.query(Notice).filter(
            Notice.audience == "manager",
            Notice.outlet_id.is_(None),
        )
    if user.role == "outlet_manager" and user.outlet_ids:
        # MULTI-OUTLET: notices for ANY of the outlets this manager is linked to.
        return db.query(Notice).filter(
            Notice.audience == "manager",
            Notice.outlet_id.in_(user.outlet_ids),
        )
    if user.is_etl_staff or user.role == "outlet_staff":
        return db.query(Notice).filter(
            Notice.audience == "staff",
            Notice.recipient_staff_id == user.id,
        )
    return db.query(Notice).filter(Notice.id < 0)  # empty set


@router.get("/", response_model=NoticeListResponse)
def list_notices(
    # Optional IST calendar day filter (YYYY-MM-DD). Omit for "all".
    date: Optional[str] = Query(None, description="IST day filter, e.g. 2026-08-24"),
    limit: int = Query(30, ge=1, le=300),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    base = _scoped_query(db, user)

    # unread_count is always the TOTAL unread in scope (drives the bell badge),
    # independent of the date filter / page.
    unread = base.filter(Notice.is_read == False).count()  # noqa: E712

    listq = base
    if date:
        try:
            start_utc, end_utc = _ist_day_utc_bounds(date)
        except ValueError:
            raise HTTPException(status_code=400, detail="date must be YYYY-MM-DD")
        listq = listq.filter(
            Notice.created_at >= start_utc,
            Notice.created_at < end_utc,
        )

    # Fetch one extra row to cheaply detect whether more pages exist.
    rows: List[Notice] = (
        listq.order_by(Notice.is_read.asc(), Notice.created_at.desc())
        .offset(offset)
        .limit(limit + 1)
        .all()
    )
    has_more = len(rows) > limit
    rows = rows[:limit]

    return NoticeListResponse(
        notices=[NoticeOut.model_validate(r) for r in rows],
        unread_count=unread,
        has_more=has_more,
    )


@router.get("/unread-count", response_model=UnreadCountResponse)
def unread_count(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    count = _scoped_query(db, user).filter(Notice.is_read == False).count()  # noqa: E712
    return UnreadCountResponse(unread_count=count)


@router.patch("/{notice_id}/read")
def mark_read(
    notice_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    notice = _scoped_query(db, user).filter(Notice.id == notice_id).first()
    if not notice:
        raise HTTPException(status_code=404, detail="Notice not found.")
    notice.is_read = True
    db.commit()
    return {"status": "ok"}


@router.patch("/read-all")
def mark_all_read(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    updated = (
        _scoped_query(db, user)
        .filter(Notice.is_read == False)  # noqa: E712
        .update({Notice.is_read: True}, synchronize_session=False)
    )
    db.commit()
    return {"status": "ok", "updated": int(updated or 0)}
