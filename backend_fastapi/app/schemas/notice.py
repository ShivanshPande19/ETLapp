# app/schemas/notice.py
from datetime import datetime, timezone
from typing import List, Optional

from pydantic import BaseModel, field_serializer


def _iso_utc_z(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.isoformat() + "Z"


class NoticeOut(BaseModel):
    id: int
    audience: str
    type: str
    court_id: Optional[int] = None
    staff_id: Optional[int] = None
    title: str
    body: Optional[str] = None
    is_read: bool
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True

    @field_serializer("created_at")
    def _ser_dt(self, dt: Optional[datetime], _info) -> Optional[str]:
        return _iso_utc_z(dt)


class NoticeListResponse(BaseModel):
    notices: List[NoticeOut]
    unread_count: int          # TOTAL unread in scope (not just this page/date)
    has_more: bool = False     # more rows exist beyond this page (for the filter)


class UnreadCountResponse(BaseModel):
    unread_count: int
