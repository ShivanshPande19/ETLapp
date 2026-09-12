import logging
from datetime import date, timedelta, datetime

from sqlalchemy.orm import Session
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy import func, or_

from ..models.sale import Outlet, DailySaleCache, Court, SalesOrder
from .sales_sources import get_adapter

logger = logging.getLogger("sales.sync")


# Bill statuses that must NOT count toward revenue (cancelled/void/refunded).
# Compared case-insensitively. Rows with a NULL status (legacy / pre-status
# data) still count, so nothing that used to be counted silently disappears.
_NON_REVENUE_STATUSES = ("cancelled", "canceled", "void", "voided", "refunded", "failed")


def _revenue_only(query):
    """Restrict a SalesOrder query to revenue-counting rows (drop cancelled)."""
    return query.filter(
        or_(
            SalesOrder.status.is_(None),
            func.lower(SalesOrder.status).notin_(_NON_REVENUE_STATUSES),
        )
    )


def _upsert(db: Session, table):
    """Return the dialect-correct INSERT construct. Both SQLite and Postgres
    expose the same `.on_conflict_do_update(index_elements=..., set_=...)` API,
    so callers stay identical across dialects."""
    dialect = db.get_bind().dialect.name
    return pg_insert(table) if dialect == "postgresql" else sqlite_insert(table)


async def sync_outlet_for_dates(
    db: Session,
    outlet: Outlet,
    api_fetch_dates: list[date],
):
    """Source-agnostic sync for one outlet.

    Picks the POS adapter from ``outlet.pos_source``, asks it for normalized
    orders across the deep-sync window, upserts them into ``sales_orders``
    (idempotent on ``(outlet_id, source, external_ref)``), then recomputes the
    affected ``DailySaleCache`` rows. The cache logic/shape is UNCHANGED — it's
    the only thing the UI reads, so the app stays byte-for-byte identical.
    """
    source = outlet.pos_source or "petpooja_generic"

    # The court's overnight cutoff (used by calendar-date sources like Petpooja
    # sales_data to attribute post-midnight bills; ignored by generic).
    cutoff_hour = 0
    if outlet.court_id:
        court = db.query(Court).filter(Court.id == outlet.court_id).first()
        cutoff_hour = (court.day_cutoff_hour or 0) if court else 0

    try:
        adapter = get_adapter(source)
    except KeyError as e:
        # Misconfigured outlet — surface it (the caller records a per-outlet
        # failure) instead of silently returning "0 orders".
        logger.error("outlet=%s unknown pos_source: %s", outlet.id, e)
        raise RuntimeError(f"Unknown POS source '{source}' for outlet {outlet.id}") from e

    try:
        orders = await adapter.fetch_normalized_orders(
            outlet, api_fetch_dates, cutoff_hour=cutoff_hour
        )
    except NotImplementedError as e:
        # Adapter deliberately has no fetch (stub) — a legitimate skip, not a
        # failure. Report zero affected dates.
        logger.info("outlet=%s source=%s not implemented, skipping: %s", outlet.id, source, e)
        return []
    except Exception as e:
        # A real fetch failure (network/POS/credentials). Do NOT swallow it as
        # an empty result — raise so /sales/sync can report the outlet failed.
        logger.exception("outlet=%s source=%s fetch failed", outlet.id, source)
        raise RuntimeError(f"Sync failed for outlet {outlet.id}") from e

    affected_business_dates = set()

    # 1. UPSERT each normalized bill into sales_orders. business_date + amount +
    #    status are updated on conflict so a re-sync self-heals any earlier row.
    for o in orders:
        affected_business_dates.add(o.business_date)
        stmt = _upsert(db, SalesOrder).values(
            outlet_id=outlet.id,
            source=source,
            external_ref=o.external_ref,
            business_date=o.business_date,
            created_on=o.created_on,
            total_amount=o.total_amount,
            status=o.status,
        ).on_conflict_do_update(
            index_elements=["outlet_id", "source", "external_ref"],
            set_={
                "total_amount": o.total_amount,
                "business_date": o.business_date,
                "status": o.status,
            },
        )
        db.execute(stmt)

    db.commit()

    # 2. Recompute DailySaleCache for each affected business day (UNCHANGED shape
    #    — now summing sales_orders instead of petpooja_orders; identical numbers
    #    after backfill). Scoped to this outlet's rows for this outlet+date.
    for b_date in affected_business_dates:
        # Exclude cancelled/void bills from the cache total (self-healing): a
        # bill cancelled after an earlier sync had its stored status updated to
        # "Cancelled" by the upsert above, so it now drops out of the total.
        stats = _revenue_only(
            db.query(
                func.sum(SalesOrder.total_amount).label("tot"),
                func.count(SalesOrder.id).label("cnt"),
            ).filter(
                SalesOrder.outlet_id == outlet.id,
                SalesOrder.business_date == b_date,
                # Scope to THIS outlet's current POS source. Without this, if an
                # outlet ever has rows under two sources (e.g. after a
                # pos_source migration where old rows were never purged), the
                # cache would SUM both sources → double-counted revenue.
                SalesOrder.source == source,
            )
        ).first()

        tot = stats.tot or 0.0
        cnt = stats.cnt or 0
        avg = round(tot / cnt, 2) if cnt > 0 else 0.0
        now = datetime.utcnow()

        cache_stmt = _upsert(db, DailySaleCache).values(
            outlet_id=outlet.id,
            sale_date=b_date,
            total_sales=tot,
            bill_count=cnt,
            avg_bill=avg,
            fetched_at=now,
        ).on_conflict_do_update(
            index_elements=["outlet_id", "sale_date"],
            set_={
                "total_sales": tot,
                "bill_count": cnt,
                "avg_bill": avg,
                "fetched_at": now,
            },
        )
        db.execute(cache_stmt)

    db.commit()
    return list(affected_business_dates)


async def resync_outlet_range(
    db: Session,
    outlet: Outlet,
    date_from: date,
    date_to: date,
    purge: bool = True,
) -> dict:
    """Repair/rebuild one outlet's sales over an explicit date range.

    Unlike the routine 3-day deep sync, this re-fetches EVERY day in
    ``[date_from, date_to]`` and (optionally) PURGES the outlet's existing rows
    for its POS source first, so a corrupted history (e.g. the daily-reset
    orderID collision) is rebuilt cleanly with the current, collision-free key.

    SAFETY: we fetch first and only purge if the fetch actually returned bills
    (or the range legitimately has none but the caller forced purge). This means
    a transient POS/network failure can never wipe good data and leave the
    outlet at ₹0 — the purge simply doesn't happen and the caller sees 0 fetched.
    """
    source = outlet.pos_source or "petpooja_generic"

    cutoff_hour = 0
    if outlet.court_id:
        court = db.query(Court).filter(Court.id == outlet.court_id).first()
        cutoff_hour = (court.day_cutoff_hour or 0) if court else 0

    adapter = get_adapter(source)

    # Requesting order_date=D on the Petpooja generic API returns bills dated D
    # AND D-1, so fetching each day in [from, to] fully covers business days
    # [from, to]. Other range-based adapters read min..max themselves.
    span = (date_to - date_from).days
    api_dates = [date_from + timedelta(days=i) for i in range(span + 1)]

    orders = await adapter.fetch_normalized_orders(
        outlet, api_dates, cutoff_hour=cutoff_hour
    )

    # Only keep bills that actually fall inside the requested window (the API
    # can hand back an adjacent day; we don't want to purge-and-rebuild dates
    # outside the caller's range).
    orders = [o for o in orders if date_from <= o.business_date <= date_to]

    if not orders and purge:
        # Nothing came back — refuse to purge so we never blank a good outlet on
        # a transient failure. Caller can retry.
        return {
            "outlet_id": outlet.id,
            "vendor_name": outlet.vendor_name,
            "purged": False,
            "fetched_orders": 0,
            "updated_business_dates": [],
            "note": "No orders returned for the range — purge skipped (safety). Retry.",
        }

    purged = 0
    if purge:
        purged = (
            db.query(SalesOrder)
            .filter(
                SalesOrder.outlet_id == outlet.id,
                SalesOrder.source == source,
                SalesOrder.business_date >= date_from,
                SalesOrder.business_date <= date_to,
            )
            .delete(synchronize_session=False)
        )
        db.commit()

    affected = set()
    for o in orders:
        affected.add(o.business_date)
        stmt = _upsert(db, SalesOrder).values(
            outlet_id=outlet.id,
            source=source,
            external_ref=o.external_ref,
            business_date=o.business_date,
            created_on=o.created_on,
            total_amount=o.total_amount,
            status=o.status,
        ).on_conflict_do_update(
            index_elements=["outlet_id", "source", "external_ref"],
            set_={
                "total_amount": o.total_amount,
                "business_date": o.business_date,
                "status": o.status,
            },
        )
        db.execute(stmt)
    db.commit()

    # Recompute cache for every affected business day (revenue-only, scoped to
    # this outlet+source) — identical logic to sync_outlet_for_dates.
    for b_date in affected:
        stats = _revenue_only(
            db.query(
                func.sum(SalesOrder.total_amount).label("tot"),
                func.count(SalesOrder.id).label("cnt"),
            ).filter(
                SalesOrder.outlet_id == outlet.id,
                SalesOrder.business_date == b_date,
                SalesOrder.source == source,
            )
        ).first()
        tot = stats.tot or 0.0
        cnt = stats.cnt or 0
        avg = round(tot / cnt, 2) if cnt > 0 else 0.0
        now = datetime.utcnow()
        cache_stmt = _upsert(db, DailySaleCache).values(
            outlet_id=outlet.id,
            sale_date=b_date,
            total_sales=tot,
            bill_count=cnt,
            avg_bill=avg,
            fetched_at=now,
        ).on_conflict_do_update(
            index_elements=["outlet_id", "sale_date"],
            set_={
                "total_sales": tot,
                "bill_count": cnt,
                "avg_bill": avg,
                "fetched_at": now,
            },
        )
        db.execute(cache_stmt)
    db.commit()

    return {
        "outlet_id": outlet.id,
        "vendor_name": outlet.vendor_name,
        "source": source,
        "purged": purged,
        "fetched_orders": len(orders),
        "updated_business_dates": sorted(str(d) for d in affected),
    }


# === ROUTE HANDLERS ===

async def sync_court_by_fetch_date(
    db: Session,
    court_uid: str,
    fetch_for_date: date,
    force_refresh: bool = True,
) -> dict:
    court = db.query(Court).filter(Court.court_uid == court_uid, Court.is_active == 1).first()
    if not court:
        raise ValueError("Court not found")

    # The 3-Day Deep Sync Window
    dates_to_fetch = [fetch_for_date, fetch_for_date - timedelta(days=1), fetch_for_date - timedelta(days=2)]
    outlets = db.query(Outlet).filter(Outlet.court_id == court.id, Outlet.is_active == 1).all()

    results = []
    failed = 0
    for outlet in outlets:
        try:
            affected_dates = await sync_outlet_for_dates(db, outlet, dates_to_fetch)
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "updated_business_dates": [str(d) for d in affected_dates],
                "ok": True,
            })
        except Exception as e:
            # One outlet failing must not abort the rest — record it and move on.
            db.rollback()
            failed += 1
            logger.error("sync failed for outlet %s (%s): %s", outlet.id, outlet.vendor_name, e)
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "updated_business_dates": [],
                "ok": False,
                "error": "sync failed",
            })

    return {
        "court_uid": court.court_uid,
        "court_name": court.name,
        "sync_trigger_date": str(fetch_for_date),
        "outlets_synced": len(outlets),
        "outlets_failed": failed,
        "details": results
    }


async def sync_all_active_outlets_by_fetch_date(
    db: Session,
    fetch_for_date: date,
    force_refresh: bool = True,
) -> dict:
    # The 3-Day Deep Sync Window Automatically applied
    dates_to_fetch = [fetch_for_date, fetch_for_date - timedelta(days=1), fetch_for_date - timedelta(days=2)]

    outlets = db.query(Outlet).filter(Outlet.is_active == 1).all()
    results = []
    failed = 0

    for outlet in outlets:
        try:
            affected_dates = await sync_outlet_for_dates(db, outlet, dates_to_fetch)
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "updated_business_dates": [str(d) for d in affected_dates],
                "ok": True,
            })
        except Exception as e:
            # One outlet failing must not abort the rest — record it and move on.
            db.rollback()
            failed += 1
            logger.error("sync failed for outlet %s (%s): %s", outlet.id, outlet.vendor_name, e)
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "updated_business_dates": [],
                "ok": False,
                "error": "sync failed",
            })

    return {
        "sync_trigger_date": str(fetch_for_date),
        "petpooja_api_date": str(fetch_for_date), # Keeping for backwards compatibility with scheduler
        "business_date": str(fetch_for_date - timedelta(days=1)), # Keeping for backwards compatibility
        "outlets_synced": len(outlets),
        "outlets_failed": failed,
        "details": results
    }
