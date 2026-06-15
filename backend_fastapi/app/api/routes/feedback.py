# app/api/routes/feedback.py

import os
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address

from ...database import get_db
from ...models.feedback import Feedback
from ...models.sale import Court, Outlet
from ...schemas.feedback import FeedbackCreate, FeedbackOut, FeedbackAnalytics
from ..deps import get_current_user, CurrentUser

logger = logging.getLogger("feedback")

router = APIRouter()

# ✅ FIX #5: limiter (shared instance also wired in main.py)
limiter = Limiter(key_func=get_remote_address)

templates_dir = os.path.join(os.getcwd(), "app", "templates")
templates = Jinja2Templates(directory=templates_dir)


# ─── Helper ──────────────────────────────────────────────────────────────────

def _to_out(f: Feedback) -> FeedbackOut:
    return FeedbackOut.from_orm_masked(f)


def _avg(values: List[int]) -> Optional[float]:
    # ✅ FIX #3: explicit half-up rounding (avoid banker's rounding surprises)
    if not values:
        return None
    raw = sum(values) / len(values)
    return float(int(raw * 10 + 0.5)) / 10


def _analytics(feedbacks: List[Feedback]) -> FeedbackAnalytics:
    total = len(feedbacks)
    court_ratings = [f.court_rating for f in feedbacks if f.court_rating]
    outlet_ratings = [f.outlet_rating for f in feedbacks if f.outlet_rating]
    all_ratings = court_ratings + outlet_ratings

    # ✅ Per-star distribution of outlet ratings (index 0 => 1★ ... index 4 => 5★)
    distribution = [0, 0, 0, 0, 0]
    for r in outlet_ratings:
        if 1 <= r <= 5:
            distribution[r - 1] += 1

    now = datetime.utcnow()
    week_start = now - timedelta(days=7)
    last_week_start = now - timedelta(days=14)

    this_week = sum(
        1 for f in feedbacks
        if f.created_at and f.created_at >= week_start
    )
    last_week = sum(
        1 for f in feedbacks
        if f.created_at
        and last_week_start <= f.created_at < week_start
    )

    return FeedbackAnalytics(
        total_count=total,
        avg_court_rating=_avg(court_ratings),
        avg_outlet_rating=_avg(outlet_ratings),
        five_star_count=sum(1 for r in all_ratings if r == 5),
        one_star_count=sum(1 for r in all_ratings if r == 1),
        this_week_count=this_week,
        last_week_count=last_week,
        rating_distribution=distribution,
    )


# ─── PUBLIC: QR Portal ───────────────────────────────────────────────────────

@router.get("/portal", response_class=HTMLResponse)
@limiter.limit("30/minute")  # ✅ FIX #6: limit portal enumeration
def serve_feedback_portal(
    request: Request,
    court_id: int = Query(1, ge=1),
    db: Session = Depends(get_db),
):
    court = db.query(Court).filter(
        Court.id == court_id, Court.is_active == 1
    ).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found.")

    court_name = court.name
    outlets = db.query(Outlet).filter(
        Outlet.court_id == court_id, Outlet.is_active == 1
    ).all()
    outlets_data = [{"id": o.id, "name": o.vendor_name} for o in outlets]

    return templates.TemplateResponse(
        request=request,
        name="feedback.html",
        context={
            "request": request,
            "court_id": court_id,
            "court_name": court_name,
            "outlets": outlets_data,
        },
    )


# ─── PUBLIC: Customer submits feedback (QR scan) ─────────────────────────────

@router.post(
    "/submit",
    response_model=FeedbackOut,
    status_code=status.HTTP_201_CREATED,
)
@limiter.limit("5/minute")  # ✅ FIX #5: anti-spam on public submit
def submit_feedback(
    request: Request,
    payload: FeedbackCreate,
    db: Session = Depends(get_db),
):
    court = db.query(Court).filter(
        Court.id == payload.court_id, Court.is_active == 1
    ).first()
    if not court:
        raise HTTPException(status_code=404, detail="Court not found.")

    if payload.outlet_id:
        outlet = db.query(Outlet).filter(
            Outlet.id == payload.outlet_id,
            Outlet.court_id == payload.court_id,
            Outlet.is_active == 1,
        ).first()
        if not outlet:
            raise HTTPException(
                status_code=404,
                detail="Outlet not found or does not belong to this court.",
            )

    try:
        new_feedback = Feedback(
            court_id=payload.court_id,
            outlet_id=payload.outlet_id,
            customer_name=payload.customer_name,
            customer_phone=payload.customer_phone,
            court_rating=payload.court_rating,
            court_comments=payload.court_comments,
            outlet_rating=payload.outlet_rating,
            outlet_comments=payload.outlet_comments,
            source=payload.source,
        )
        db.add(new_feedback)
        db.commit()
        db.refresh(new_feedback)
        return _to_out(new_feedback)
    except Exception as e:
        db.rollback()
        # ✅ FIX #9: log real error server-side, generic msg to client
        logger.exception("Failed to save feedback: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save feedback.",
        )


# ─── PROTECTED: ETL Manager — all feedbacks ──────────────────────────────────

@router.get("/court/{court_id}", response_model=List[FeedbackOut])
def get_court_feedbacks(
    court_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    feedbacks = (
        db.query(Feedback)
        .filter(Feedback.court_id == court_id)
        .order_by(Feedback.created_at.desc())
        .all()
    )
    return [_to_out(f) for f in feedbacks]


@router.get("/court/{court_id}/analytics", response_model=FeedbackAnalytics)
def get_court_analytics(
    court_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    feedbacks = db.query(Feedback).filter(
        Feedback.court_id == court_id
    ).all()
    return _analytics(feedbacks)


# ─── PROTECTED: Outlet Manager/Staff — own outlet only ───────────────────────

@router.get("/outlet/{outlet_id}", response_model=List[FeedbackOut])
def get_outlet_feedbacks(
    outlet_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
    # ✅ Pagination: page through reviews instead of loading every row at once.
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    # ✅ Optional day filter. Client sends the local-day boundaries already
    # converted to UTC, so filtering stays correct across timezones.
    start: Optional[datetime] = Query(None),
    end: Optional[datetime] = Query(None),
):
    if user.is_outlet_user:
        if user.outlet_id != outlet_id:
            raise HTTPException(
                status_code=403,
                detail="You can only view your own outlet's feedbacks.",
            )
    elif not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="Access denied.")

    query = db.query(Feedback).filter(
        Feedback.outlet_id == outlet_id,
        Feedback.outlet_rating.isnot(None),
    )

    # created_at is stored as naive UTC (datetime.utcnow). Normalise incoming
    # bounds to naive UTC so comparisons line up regardless of client tz info.
    if start is not None:
        if start.tzinfo is not None:
            start = start.astimezone(timezone.utc).replace(tzinfo=None)
        query = query.filter(Feedback.created_at >= start)
    if end is not None:
        if end.tzinfo is not None:
            end = end.astimezone(timezone.utc).replace(tzinfo=None)
        query = query.filter(Feedback.created_at < end)

    feedbacks = (
        query.order_by(Feedback.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [_to_out(f) for f in feedbacks]


@router.get("/outlet/{outlet_id}/analytics", response_model=FeedbackAnalytics)
def get_outlet_analytics(
    outlet_id: int,
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if user.is_outlet_user:
        if user.outlet_id != outlet_id:
            raise HTTPException(status_code=403, detail="Access denied.")
    elif not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="Access denied.")

    feedbacks = db.query(Feedback).filter(
        Feedback.outlet_id == outlet_id,
        Feedback.outlet_rating.isnot(None),
    ).all()
    return _analytics(feedbacks)


# ─── PROTECTED: All feedbacks (ETL manager only) ─────────────────────────────

@router.get("/all", response_model=List[FeedbackOut])
def get_all_feedbacks(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    feedbacks = (
        db.query(Feedback)
        .order_by(Feedback.created_at.desc())
        .all()
    )
    return [_to_out(f) for f in feedbacks]


@router.get("/all/analytics", response_model=FeedbackAnalytics)
def get_all_analytics(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    feedbacks = db.query(Feedback).all()
    return _analytics(feedbacks)
