from datetime import date, timedelta, datetime

from sqlalchemy.orm import Session
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy import func

from ..models.sale import Outlet, DailySaleCache, Court, SalesOrder
from .sales_sources import get_adapter


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
        print(f"[SYNC ERROR] outlet={outlet.id} unknown pos_source: {e}")
        return []

    try:
        orders = await adapter.fetch_normalized_orders(
            outlet, api_fetch_dates, cutoff_hour=cutoff_hour
        )
    except NotImplementedError as e:
        print(f"[SYNC SKIP] outlet={outlet.id} source={source}: {e}")
        return []
    except Exception as e:
        print(f"[SYNC ERROR] outlet={outlet.id} source={source} fetch failed: {e}")
        return []

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
        stats = db.query(
            func.sum(SalesOrder.total_amount).label("tot"),
            func.count(SalesOrder.id).label("cnt"),
        ).filter(
            SalesOrder.outlet_id == outlet.id,
            SalesOrder.business_date == b_date,
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
    for outlet in outlets:
        affected_dates = await sync_outlet_for_dates(db, outlet, dates_to_fetch)
        results.append({
            "outlet_id": outlet.id,
            "vendor_name": outlet.vendor_name,
            "updated_business_dates": [str(d) for d in affected_dates]
        })

    return {
        "court_uid": court.court_uid,
        "court_name": court.name,
        "sync_trigger_date": str(fetch_for_date),
        "outlets_synced": len(outlets),
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

    for outlet in outlets:
        affected_dates = await sync_outlet_for_dates(db, outlet, dates_to_fetch)
        results.append({
            "outlet_id": outlet.id,
            "vendor_name": outlet.vendor_name,
            "updated_business_dates": [str(d) for d in affected_dates]
        })

    return {
        "sync_trigger_date": str(fetch_for_date),
        "petpooja_api_date": str(fetch_for_date), # Keeping for backwards compatibility with scheduler
        "business_date": str(fetch_for_date - timedelta(days=1)), # Keeping for backwards compatibility
        "outlets_synced": len(outlets),
        "details": results
    }
