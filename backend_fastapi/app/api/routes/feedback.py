# app/api/routes/feedback.py

import os
import logging
from datetime import datetime, timedelta, timezone
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address

from ...database import get_db
from ...models.feedback import Feedback
from ...models.sale import Court, Outlet
from ...schemas.feedback import FeedbackCreate, FeedbackOut, FeedbackAnalytics
from ...schemas.court import validate_google_review_url
from ...services.notice_service import create_notice
from ..deps import get_current_user, CurrentUser
from .events import fire_notify

logger = logging.getLogger("feedback")

router = APIRouter()

# ✅ FIX #5: limiter (shared instance also wired in main.py)
limiter = Limiter(key_func=get_remote_address)

templates_dir = os.path.join(os.getcwd(), "app", "templates")
templates = Jinja2Templates(directory=templates_dir)


# ─── Helper ──────────────────────────────────────────────────────────────────

def _to_out(f: Feedback) -> FeedbackOut:
    return FeedbackOut.from_orm_masked(f)


def _normalize_utc(dt: Optional[datetime]) -> Optional[datetime]:
    """Convert an incoming (possibly tz-aware) datetime to naive UTC so it
    compares correctly against created_at (stored as naive UTC)."""
    if dt is None:
        return None
    if dt.tzinfo is not None:
        return dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def _apply_date_range(query, start: Optional[datetime], end: Optional[datetime]):
    """Apply optional [start, end) created_at bounds to a feedback query."""
    start = _normalize_utc(start)
    end = _normalize_utc(end)
    if start is not None:
        query = query.filter(Feedback.created_at >= start)
    if end is not None:
        query = query.filter(Feedback.created_at < end)
    return query


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
        # ✅ Count per FEEDBACK (any 5★/1★ rating), not per rating-instance — so
        # these stay consistent with total_count (a single feedback with both a
        # court 5★ and an outlet 5★ counts once, not twice).
        five_star_count=sum(
            1 for f in feedbacks
            if f.court_rating == 5 or f.outlet_rating == 5
        ),
        one_star_count=sum(
            1 for f in feedbacks
            if f.court_rating == 1 or f.outlet_rating == 1
        ),
        this_week_count=this_week,
        last_week_count=last_week,
        rating_distribution=distribution,
        # How many of these customers we handed off to Google (see
        # GET /{feedback_id}/google). Not a count of posted reviews — Google
        # gives us no way to confirm those.
        google_cta_click_count=sum(
            1 for f in feedbacks
            if getattr(f, "google_cta_clicked_at", None) is not None
        ),
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
            # Only a BOOLEAN reaches the page — never the URL itself. The
            # thank-you screen links to our own /feedback/{id}/google, which
            # resolves the real destination server-side. That keeps the click
            # measurable and means the redirect target can be corrected
            # without touching anything already rendered on a customer phone.
            "has_google_review": bool(
                (getattr(court, "google_review_url", None) or "").strip()
            ),
        },
    )


# ─── PUBLIC: Customer submits feedback (QR scan) ─────────────────────────────

# ─── Durable notices (+ push) for new feedback ───────────────────────────────
#
# Submitted by an anonymous QR customer, so there is nobody to notify back —
# these all go to staff-side personas.
#
# PRIVACY: the payload must never carry `customer_phone`. The API masks it
# (_to_out → FeedbackOut.from_orm_masked) but the raw value is in the DB, and a
# push notification renders on a LOCK SCREEN. Only name + rating + comment.

_LOW_RATING_THRESHOLD = 2  # 1★ and 2★ count as an escalation


def _rating_stars(rating: Optional[int]) -> str:
    if not rating:
        return ""
    return "★" * int(rating)


def _notify_feedback(db: Session, fb: Feedback) -> None:
    """Fan out a new feedback to the personas that can act on it."""
    try:
        who = (fb.customer_name or "A customer").strip()

        # ── Outlet review → ONLY that outlet's manager. ───────────────────────
        # Trigger #15. Previously undeliverable: SSE keys on court_id, so the
        # outlet manager could never be addressed.
        if fb.outlet_id and fb.outlet_rating:
            low = fb.outlet_rating <= _LOW_RATING_THRESHOLD
            comment = (fb.outlet_comments or "").strip()
            create_notice(
                db,
                audience="manager",
                type="feedback_low" if low else "feedback_new",
                title=(
                    f"{_rating_stars(fb.outlet_rating)} review needs attention"
                    if low
                    else f"New {_rating_stars(fb.outlet_rating)} review"
                ),
                body=(
                    f"{who} rated your outlet {fb.outlet_rating}/5"
                    + (f': "{comment[:140]}"' if comment else ".")
                ),
                outlet_id=fb.outlet_id,
            )

        # ── Court review → ETL manager tier. ─────────────────────────────────
        # Trigger #14.
        if fb.court_rating:
            low = fb.court_rating <= _LOW_RATING_THRESHOLD
            comment = (fb.court_comments or "").strip()
            create_notice(
                db,
                audience="manager",
                type="feedback_low" if low else "feedback_new",
                title=(
                    f"{_rating_stars(fb.court_rating)} court review needs attention"
                    if low
                    else f"New {_rating_stars(fb.court_rating)} court review"
                ),
                body=(
                    f"{who} rated the court {fb.court_rating}/5"
                    + (f': "{comment[:140]}"' if comment else ".")
                ),
                court_id=fb.court_id,
                outlet_id=None,
            )

        # ── Trigger #16: a low outlet rating is also an ETL-level escalation. ─
        # The outlet manager was told above; the ETL manager needs to know a
        # vendor in their court is being rated badly.
        if fb.outlet_id and fb.outlet_rating and fb.outlet_rating <= _LOW_RATING_THRESHOLD:
            outlet = db.query(Outlet).filter(Outlet.id == fb.outlet_id).first()
            create_notice(
                db,
                audience="manager",
                type="feedback_low",
                title=f"{_rating_stars(fb.outlet_rating)} rating for an outlet",
                body=(
                    f"{(outlet.vendor_name if outlet else 'An outlet')} received "
                    f"{fb.outlet_rating}/5 from {who}."
                ),
                court_id=fb.court_id,
                outlet_id=None,
            )
    except Exception as e:  # noqa: BLE001 — never break a public submit
        logger.error("[FEEDBACK] notice fan-out failed for #%s: %s", fb.id, e)


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

        # ✅ Live SSE ping so managers/staff screens refresh instantly.
        # Routed to the court channel (+ managers on court_id 0). Clients
        # re-fetch their own role-scoped feedback lists.
        fire_notify(
            {
                "type": "feedback_update",
                "court_id": new_feedback.court_id or 0,
                "outlet_id": new_feedback.outlet_id,
                "feedback_id": new_feedback.id,
            }
        )

        _notify_feedback(db, new_feedback)
        return _to_out(new_feedback)
    except Exception as e:
        db.rollback()
        # ✅ FIX #9: log real error server-side, generic msg to client
        logger.exception("Failed to save feedback: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save feedback.",
        )


# ─── PUBLIC: hand off to Google reviews (tracked) ────────────────────────────
#
# Reached when a customer taps "also review us on Google" on the thank-you
# screen, AFTER their feedback is already committed. Nothing here can affect
# the stored feedback — by the time this runs, our data is safe.
#
# Why bounce through our own server instead of linking Google directly:
#   1. It makes the hand-off measurable (google_cta_clicked_at).
#   2. The destination stays server-side, so a wrong/expired review link can be
#      fixed for everyone without reprinting a QR or re-rendering a page.
#
# IMPORTANT — this is a redirect to an operator-supplied URL, i.e. exactly the
# shape of an open-redirect bug. The URL is allowlisted to Google hosts when it
# is SAVED (schemas/court.py), and re-checked HERE before redirecting, because
# a value written to the DB by any other path (manual SQL, seed script, an older
# build) would otherwise be trusted blindly.
#
# Declared before /court/{court_id} etc. is safe: the second segment must match
# the literal "google", so /feedback/court/5 can never fall into this route.

@router.get("/{feedback_id}/google", include_in_schema=False)
@limiter.limit("30/minute")
def google_review_handoff(
    request: Request,
    feedback_id: int,
    db: Session = Depends(get_db),
):
    """Record the Google hand-off for this feedback, then redirect to Google."""
    fb = db.query(Feedback).filter(Feedback.id == feedback_id).first()
    if not fb:
        raise HTTPException(status_code=404, detail="Feedback not found.")

    court = db.query(Court).filter(Court.id == fb.court_id).first()
    raw_url = (getattr(court, "google_review_url", None) or "").strip() if court else ""
    if not raw_url:
        # No link configured for this court — the CTA should not have rendered.
        raise HTTPException(status_code=404, detail="No review link for this court.")

    try:
        target = validate_google_review_url(raw_url)
    except ValueError:
        # Stored value is not a Google URL: refuse to bounce the customer to it.
        logger.error(
            "[FEEDBACK] court %s has a non-Google google_review_url; refusing redirect",
            fb.court_id,
        )
        raise HTTPException(status_code=404, detail="No review link for this court.")

    if not target:
        raise HTTPException(status_code=404, detail="No review link for this court.")

    # Stamp only the FIRST tap, so the metric counts people, not taps (and a
    # reloaded/shared link can't inflate it further).
    if fb.google_cta_clicked_at is None:
        try:
            fb.google_cta_clicked_at = datetime.utcnow()
            db.commit()
        except Exception as e:  # noqa: BLE001 — tracking must never block the hand-off
            db.rollback()
            logger.error(
                "[FEEDBACK] failed to stamp google CTA for #%s: %s", feedback_id, e
            )

    # 302: deliberately not a permanent redirect — the destination is
    # operator-editable, so browsers must not cache it.
    return RedirectResponse(url=target, status_code=status.HTTP_302_FOUND)


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


# ─── PROTECTED: ETL Staff — own assigned court (COURT feedback only) ─────────

@router.get("/my-court", response_model=List[FeedbackOut])
def get_my_court_feedbacks(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
    # ETL managers have no single court — they may optionally focus one court.
    court_id: Optional[int] = Query(None),
    # ✅ Pagination so the staff list never loads every row at once.
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
    # ✅ Optional day filter (client sends local-day boundaries already in UTC).
    start: Optional[datetime] = Query(None),
    end: Optional[datetime] = Query(None),
):
    """ETL staff (and ETL managers) view the COURT-level feedback for the
    court assigned to them. Only feedbacks that actually carry a court rating
    are returned — outlet-only reviews are intentionally hidden so staff see
    just the venue/court voice."""
    if not (user.is_etl_staff or user.is_etl_manager):
        raise HTTPException(status_code=403, detail="Court staff access required.")

    # ETL staff are locked to their assigned court. An ETL MANAGER has no single
    # court (court_id is always None for a manager identity) — previously that
    # made this endpoint always 403 for managers. They now see court feedback
    # across all courts (matching their company-wide scope), or a single court
    # when ?court_id= is supplied.
    court_filter = user.court_id
    if user.is_etl_manager and not user.is_etl_staff:
        court_filter = court_id
    elif user.court_id is None:
        raise HTTPException(
            status_code=403,
            detail="No court assigned to your account.",
        )

    query = db.query(Feedback).filter(Feedback.court_rating.isnot(None))
    if court_filter is not None:
        query = query.filter(Feedback.court_id == court_filter)
    query = _apply_date_range(query, start, end)

    feedbacks = (
        query.order_by(Feedback.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [_to_out(f) for f in feedbacks]


@router.get("/my-court/analytics", response_model=FeedbackAnalytics)
def get_my_court_analytics(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
    # ETL managers have no single court — they may optionally focus one court.
    court_id: Optional[int] = Query(None),
):
    """Overall court-feedback analytics for the staff's assigned court (or, for
    an ETL manager, across all courts / an optional ?court_id=)."""
    if not (user.is_etl_staff or user.is_etl_manager):
        raise HTTPException(status_code=403, detail="Court staff access required.")

    court_filter = user.court_id
    if user.is_etl_manager and not user.is_etl_staff:
        court_filter = court_id
    elif user.court_id is None:
        raise HTTPException(
            status_code=403,
            detail="No court assigned to your account.",
        )

    query = db.query(Feedback).filter(Feedback.court_rating.isnot(None))
    if court_filter is not None:
        query = query.filter(Feedback.court_id == court_filter)
    return _analytics(query.all())


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
        if outlet_id not in user.outlet_ids:  # MULTI-OUTLET: any of their outlets
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

    # created_at is stored as naive UTC. Client sends local-day bounds already
    # converted to UTC, so filtering stays correct across timezones.
    query = _apply_date_range(query, start, end)

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
        if outlet_id not in user.outlet_ids:  # MULTI-OUTLET
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
    # ✅ Server-side filters (ETL manager view).
    court_id: Optional[int] = Query(None, ge=1),
    outlet_id: Optional[int] = Query(None, ge=1),
    start: Optional[datetime] = Query(None),
    end: Optional[datetime] = Query(None),
    # ✅ Pagination.
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    query = db.query(Feedback)
    if court_id is not None:
        query = query.filter(Feedback.court_id == court_id)
    if outlet_id is not None:
        query = query.filter(Feedback.outlet_id == outlet_id)
    query = _apply_date_range(query, start, end)

    feedbacks = (
        query.order_by(Feedback.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    return [_to_out(f) for f in feedbacks]


@router.get("/all/analytics", response_model=FeedbackAnalytics)
def get_all_analytics(
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
    # ✅ Same filters as /all so the analytics card matches the visible list.
    court_id: Optional[int] = Query(None, ge=1),
    outlet_id: Optional[int] = Query(None, ge=1),
    start: Optional[datetime] = Query(None),
    end: Optional[datetime] = Query(None),
):
    if not user.is_etl_manager:
        raise HTTPException(status_code=403, detail="ETL manager access required.")

    query = db.query(Feedback)
    if court_id is not None:
        query = query.filter(Feedback.court_id == court_id)
    if outlet_id is not None:
        query = query.filter(Feedback.outlet_id == outlet_id)
    query = _apply_date_range(query, start, end)

    return _analytics(query.all())
