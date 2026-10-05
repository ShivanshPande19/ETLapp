from datetime import date, timedelta
from typing import Optional

from fastapi import APIRouter, Query, HTTPException, Depends
from sqlalchemy.orm import Session

from ...database import get_db
from ...core.query_utils import now_ist
from ...schemas.sale import (
    SalesSummaryResponse, VendorHistoryResponse, SalesTrendResponse, SalesCompareResponse,
)
from ...services.sales_service import (
    get_sales_summary, get_vendor_history, get_sales_trend, get_sales_comparison,
)
from ...services.petpooja_service import (
    sync_court_by_fetch_date,
    sync_all_active_outlets_by_fetch_date,
    resync_outlet_range,
)
from ...models.sale import Outlet
from ..deps import get_current_user, require_etl_manager, CurrentUser

router = APIRouter()


def _zone_outlet_ids(db: Session, court_ids: list[int]) -> list[int]:
    """All active outlet ids in the given courts — used to aggregate a zone
    manager's 'all my zones' sales view. Empty list ⇒ the service's `or [-1]`
    sentinel returns nothing (never all)."""
    if not court_ids:
        return []
    rows = (
        db.query(Outlet.id)
        .filter(Outlet.court_id.in_(court_ids), Outlet.is_active == 1)
        .all()
    )
    return [r[0] for r in rows]


def _scope_outlets(
    user: CurrentUser,
    court_id: Optional[int],
    outlet_id: Optional[int],
    db: Session,
) -> tuple[Optional[int], Optional[int], Optional[list[int]]]:
    """Constrain a summary/trend request to what `user` may read.

    Returns ``(court_id, outlet_id, outlet_ids)`` to pass to the service.

    SECURITY (P0 + MULTI-OUTLET): the client can never widen its own scope.
      • ETL manager   → unrestricted; client court_id/outlet_id honored
                        (both None = whole company).
      • Zone manager  → VIEW-ONLY, locked to its assigned court(s). A specific
                        court/outlet must be within its zones; otherwise it
                        aggregates across all outlets in those zones.
      • Outlet user   → if a specific outlet_id is requested it MUST be one of
                        theirs (else 403); otherwise aggregate across ALL their
                        outlets (multi-outlet owner "all my outlets" view).
      • ETL staff     → locked to their own court.
    """
    if user.is_etl_manager:
        return court_id, outlet_id, None
    if user.is_zone_manager:
        allowed = set(user.court_ids)
        if not allowed:
            raise HTTPException(status_code=403, detail="No zone assigned to your account.")
        if outlet_id is not None:
            o = db.query(Outlet).filter(Outlet.id == outlet_id).first()
            if not o or o.court_id not in allowed:
                raise HTTPException(status_code=403, detail="You cannot access that outlet.")
            return None, outlet_id, None
        if court_id is not None:
            if court_id not in allowed:
                raise HTTPException(status_code=403, detail="You cannot access that court.")
            return court_id, None, None
        # No specific selection → aggregate across every outlet in the zones.
        return None, None, _zone_outlet_ids(db, list(allowed))
    if user.is_outlet_user:
        if not user.outlet_ids:
            raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
        if outlet_id is not None:
            if outlet_id not in user.outlet_ids:
                raise HTTPException(status_code=403, detail="You cannot access that outlet.")
            return None, outlet_id, None
        # No specific selection → all of the owner's outlets, aggregated.
        return None, None, list(user.outlet_ids)
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id, None, None
    raise HTTPException(status_code=403, detail="Access denied.")


def _scope_single_outlet(
    user: CurrentUser,
    court_id: Optional[int],
    outlet_id: Optional[int],
    vendor_name: Optional[str],
    db: Session,
) -> tuple[Optional[int], Optional[int], Optional[str]]:
    """Vendor history returns ONE vendor's series, so resolve to a single
    outlet the caller may access."""
    if user.is_etl_manager:
        return court_id, outlet_id, vendor_name
    if user.is_zone_manager:
        allowed = set(user.court_ids)
        if not allowed:
            raise HTTPException(status_code=403, detail="No zone assigned to your account.")
        if outlet_id is None:
            raise HTTPException(status_code=400, detail="outlet_id is required.")
        o = db.query(Outlet).filter(Outlet.id == outlet_id).first()
        if not o or o.court_id not in allowed:
            raise HTTPException(status_code=403, detail="You cannot access that outlet.")
        return None, outlet_id, None
    if user.is_outlet_user:
        if not user.outlet_ids:
            raise HTTPException(status_code=403, detail="No outlet assigned to your account.")
        target = outlet_id
        if target is None and len(user.outlet_ids) == 1:
            target = user.outlet_ids[0]
        if target is None:
            raise HTTPException(status_code=400, detail="outlet_id is required.")
        if target not in user.outlet_ids:
            raise HTTPException(status_code=403, detail="You cannot access that outlet.")
        return None, target, None
    if user.is_etl_staff:
        if user.court_id is None:
            raise HTTPException(status_code=403, detail="No court assigned to your account.")
        return user.court_id, None, vendor_name
    raise HTTPException(status_code=403, detail="Access denied.")


@router.get("/summary", response_model=SalesSummaryResponse)
async def sales_summary(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None), # ✅ NAYA: Outlet ID parameter
    period: str = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    court_id, outlet_id, outlet_ids = _scope_outlets(user, court_id, outlet_id, db)
    return await get_sales_summary(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id, # ✅ Service ko pass kar diya
        outlet_ids=outlet_ids,
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/trend", response_model=SalesTrendResponse)
async def sales_trend(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),
    period: str = Query("yesterday"),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    court_id, outlet_id, outlet_ids = _scope_outlets(user, court_id, outlet_id, db)
    return await get_sales_trend(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id,
        outlet_ids=outlet_ids,
        period=period,
        date_from=date_from,
        date_to=date_to,
    )


@router.get("/compare", response_model=SalesCompareResponse)
async def sales_compare(
    granularity: str = Query("week", description="week | month | year"),
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Fair same-span comparison (this-period-so-far vs the same days last
    period) with an aligned bucket series for a side-by-side chart. Scoped to
    exactly what the caller may read, just like /summary and /trend."""
    court_id, outlet_id, outlet_ids = _scope_outlets(user, court_id, outlet_id, db)
    return await get_sales_comparison(
        db=db,
        court_id=court_id,
        outlet_id=outlet_id,
        outlet_ids=outlet_ids,
        granularity=granularity,
    )


@router.get("/vendor/history", response_model=VendorHistoryResponse)
async def vendor_history(
    vendor_name: Optional[str] = Query(None), # ✅ NAYA: Made optional
    court_id: Optional[int] = Query(None),    # ✅ NAYA: Made optional
    outlet_id: Optional[int] = Query(None),   # ✅ NAYA: Added outlet_id
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    court_id, outlet_id, vendor_name = _scope_single_outlet(
        user, court_id, outlet_id, vendor_name, db
    )
    try:
        return await get_vendor_history(
            db=db,
            vendor_name=vendor_name,
            court_id=court_id,
            outlet_id=outlet_id, # ✅ Service ko id pass kardi
        )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/sync")
async def sync_sales(
    fetch_for_date: str = Query(..., description="Date to send to Petpooja, e.g. 2026-05-16"),
    court_uid: Optional[str] = Query(None, description="Optional court UID; if omitted all active outlets sync"),
    force_refresh: bool = Query(True),
    db: Session = Depends(get_db),
    # SECURITY (P0-1): triggering a POS fetch is an ETL-manager-only action.
    user: CurrentUser = Depends(require_etl_manager),
):
    try:
        parsed_fetch_date = date.fromisoformat(fetch_for_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid fetch_for_date. Use YYYY-MM-DD")

    try:
        if court_uid:
            result = await sync_court_by_fetch_date(
                db=db,
                court_uid=court_uid,
                fetch_for_date=parsed_fetch_date,
                force_refresh=force_refresh,
            )
        else:
            result = await sync_all_active_outlets_by_fetch_date(
                db=db,
                fetch_for_date=parsed_fetch_date,
                force_refresh=force_refresh,
            )
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

    # If we attempted outlets and EVERY one failed, this is a real failure —
    # don't report it as a 200 "success" (which is what used to happen). The
    # per-outlet details still show which ones failed.
    attempted = result.get("outlets_synced", 0)
    failed = result.get("outlets_failed", 0)
    if attempted > 0 and failed >= attempted:
        raise HTTPException(
            status_code=502,
            detail="Sales sync failed for all outlets — check POS credentials / connectivity.",
        )
    return result


@router.post("/resync")
async def resync_outlet(
    outlet_id: int = Query(..., description="Outlet to repair/rebuild"),
    date_from: str = Query(..., description="Start business date, YYYY-MM-DD"),
    date_to: str = Query(..., description="End business date, YYYY-MM-DD (inclusive)"),
    purge: bool = Query(True, description="Delete the outlet's existing rows in the range first (clean rebuild)"),
    db: Session = Depends(get_db),
    # ETL-manager-only: this purges + re-fetches an outlet's history.
    user: CurrentUser = Depends(require_etl_manager),
):
    """Repair one outlet's sales over an explicit date range.

    Re-fetches every day in the range from the outlet's POS and (by default)
    purges the outlet's existing rows for that range first, so a corrupted
    history — e.g. the daily-reset orderID collision that made per-day totals
    read ₹0 / partial — is rebuilt cleanly with the current collision-free key.
    Also doubles as a gap-healer for any window the routine 3-day sync missed.
    """
    try:
        d_from = date.fromisoformat(date_from)
        d_to = date.fromisoformat(date_to)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date. Use YYYY-MM-DD")
    if d_from > d_to:
        raise HTTPException(status_code=400, detail="date_from must be <= date_to")
    # Guard against an accidentally huge range (one Petpooja call per day).
    if (d_to - d_from).days > 400:
        raise HTTPException(status_code=400, detail="Range too large (max 400 days).")

    outlet = db.query(Outlet).filter(Outlet.id == outlet_id).first()
    if not outlet:
        raise HTTPException(status_code=404, detail="Outlet not found.")

    try:
        result = await resync_outlet_range(
            db=db, outlet=outlet, date_from=d_from, date_to=d_to, purge=purge
        )
    except Exception:
        db.rollback()
        raise HTTPException(status_code=502, detail="Resync failed — check POS credentials / connectivity.")
    return result


# ─── Self-healing on-demand refresh (any in-scope user) ──────────────────────
#
# Pull-to-refresh on the Sales screen triggers this. It re-fetches the caller's
# CURRENT scope + day(s) straight from the POS and recomputes DailySaleCache, so
# a day that read ₹0 (because the scheduled sync ran before the POS had posted)
# self-corrects immediately instead of waiting for the next scheduled sync.
#
# Unlike /sync and /resync (ETL-manager-only, whole-court/arbitrary-range tools),
# this is available to EVERY authenticated user but strictly scoped by
# _scope_outlets — you can only refresh outlets you can already read. Caps keep a
# user-initiated refresh cheap (one POS call per day per outlet).

# Caps so a refresh can never fan out into a huge POS job.
_REFRESH_MAX_OUTLETS = 40
_REFRESH_MAX_DAYS = 7


def _refresh_target_outlets(
    db: Session,
    court_id: Optional[int],
    outlet_id: Optional[int],
    outlet_ids: Optional[list[int]],
) -> list[Outlet]:
    """Active outlets to re-sync, from the already scope-checked tuple returned
    by _scope_outlets (so this can never widen the caller's scope)."""
    q = db.query(Outlet).filter(Outlet.is_active == 1)
    if outlet_id is not None:
        q = q.filter(Outlet.id == outlet_id)
    elif outlet_ids is not None:
        if not outlet_ids:
            return []
        q = q.filter(Outlet.id.in_(outlet_ids))
    elif court_id is not None:
        q = q.filter(Outlet.court_id == court_id)
    # else: ETL manager, whole company → every active outlet.
    return q.all()


def _refresh_date_window(
    date_from: Optional[str], date_to: Optional[str]
) -> tuple[date, date]:
    """Day(s) to re-sync. Defaults to IST 'yesterday' (the day most likely to be
    stale at ₹0); honours an explicit window but caps the span so a refresh stays
    cheap (one POS call per day per outlet)."""
    if date_from and date_to:
        try:
            d_from = date.fromisoformat(date_from)
            d_to = date.fromisoformat(date_to)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date. Use YYYY-MM-DD")
        if d_from > d_to:
            d_from, d_to = d_to, d_from
        # Only heal the most recent window — clamp to the last N days.
        if (d_to - d_from).days > _REFRESH_MAX_DAYS - 1:
            d_from = d_to - timedelta(days=_REFRESH_MAX_DAYS - 1)
        return d_from, d_to
    # A preset (yesterday/week/month/…) sends no explicit window → heal yesterday.
    yesterday = now_ist().date() - timedelta(days=1)
    return yesterday, yesterday


@router.post("/refresh")
async def refresh_sales(
    court_id: Optional[int] = Query(None),
    outlet_id: Optional[int] = Query(None),
    date_from: Optional[str] = Query(None),
    date_to: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    user: CurrentUser = Depends(get_current_user),
):
    """Self-healing POS re-sync for the caller's current scope + day(s).

    Scope is resolved with the SAME rules as /summary (_scope_outlets): a user
    can only ever refresh outlets it can already read — no privilege escalation.
    Each outlet syncs in its own transaction (one failure never aborts the rest),
    and resync_outlet_range's safety means a transient POS failure can never
    blank a good day to ₹0.
    """
    s_court_id, s_outlet_id, s_outlet_ids = _scope_outlets(user, court_id, outlet_id, db)
    outlets = _refresh_target_outlets(db, s_court_id, s_outlet_id, s_outlet_ids)
    d_from, d_to = _refresh_date_window(date_from, date_to)

    capped = len(outlets) > _REFRESH_MAX_OUTLETS
    outlets = outlets[:_REFRESH_MAX_OUTLETS]

    synced = 0
    failed = 0
    for outlet in outlets:
        try:
            await resync_outlet_range(
                db=db, outlet=outlet, date_from=d_from, date_to=d_to, purge=True
            )
            synced += 1
        except Exception:
            db.rollback()
            failed += 1

    return {
        "outlets": len(outlets),
        "synced": synced,
        "failed": failed,
        "date_from": d_from.isoformat(),
        "date_to": d_to.isoformat(),
        "capped": capped,
    }
