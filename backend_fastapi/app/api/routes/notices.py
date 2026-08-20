# app/api/routes/notices.py
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

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
    limit: int = 100,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    q = _scoped_query(db, user)
    rows: List[Notice] = (
        q.order_by(Notice.is_read.asc(), Notice.created_at.desc())
        .limit(max(1, min(limit, 300)))
        .all()
    )
    unread = q.filter(Notice.is_read == False).count()  # noqa: E712
    return NoticeListResponse(
        notices=[NoticeOut.model_validate(r) for r in rows],
        unread_count=unread,
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
