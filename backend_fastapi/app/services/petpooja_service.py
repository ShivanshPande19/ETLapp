import json
from datetime import date, timedelta, datetime

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy import func

from ..core.config import settings
from ..models.sale import Outlet, DailySaleCache, Court, PetpoojaOrder

PETPOOJA_URL = "https://api.petpooja.com/V1/thirdparty/generic_get_orders/"


def _upsert(db: Session, table):
    """Return the dialect-correct INSERT construct. Both SQLite and Postgres
    expose the same `.on_conflict_do_update(index_elements=..., set_=...)` API,
    so callers stay identical across dialects."""
    dialect = db.get_bind().dialect.name
    return pg_insert(table) if dialect == "postgresql" else sqlite_insert(table)


async def fetch_raw(
    rest_id: str,
    order_date: str,
    app_key: str | None = None,
    app_secret: str | None = None,
    access_token: str | None = None,
    cookie: str | None = None,
) -> dict:
    # Per-outlet creds if provided (non-empty), else fall back to global .env.
    payload = {
        "app_key": app_key or settings.PETPOOJA_APP_KEY,
        "app_secret": app_secret or settings.PETPOOJA_APP_SECRET,
        "access_token": access_token or settings.PETPOOJA_ACCESS_TOKEN,
        "restID": rest_id,
        "order_date": order_date,
        "refId": "",
    }

    headers = {
        "Content-Type": "application/json",
        "Cookie": f"PETPOOJA_API={cookie or settings.PETPOOJA_COOKIE}",
    }

    print(f"[PETPOOJA FETCH START] rest_id={rest_id} order_date={order_date}")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.request(
            method="GET",
            url=PETPOOJA_URL,
            headers=headers,
            json=payload,
        )
        print(f"[PETPOOJA FETCH HTTP] rest_id={rest_id} status_code={resp.status_code}")
        resp.raise_for_status()
        raw = resp.json()

    orders = raw.get("order_json", []) or raw.get("orderjson", []) or []
    print(
        f"[PETPOOJA FETCH SUCCESS] rest_id={rest_id} "
        f"success={raw.get('success')} code={raw.get('code')} orders={len(orders)}"
    )
    return raw


def extract_orders(raw: dict) -> list:
    return raw.get("order_json", []) or raw.get("orderjson", []) or []


def is_success(raw: dict) -> bool:
    return str(raw.get("success")) == "1" or str(raw.get("code")) == "200"


async def sync_outlet_for_dates(
    db: Session,
    outlet: Outlet,
    api_fetch_dates: list[date]
):
    affected_business_dates = set()
    
    # 1. T, T-1, T-2 ka data fetch karke aapas mein merge karna
    for api_date in api_fetch_dates:
        api_date_str = api_date.strftime("%Y-%m-%d")
        print(f"[FETCHING] vendor={outlet.vendor_name} date={api_date_str}")
        
        try:
            raw = await fetch_raw(
                outlet.rest_id,
                api_date_str,
                app_key=outlet.pp_app_key,
                app_secret=outlet.pp_app_secret,
                access_token=outlet.pp_access_token,
                cookie=outlet.pp_cookie,
            )
        except Exception as e:
            print(f"[PETPOOJA ERROR] Exception while fetching {outlet.rest_id} on {api_date_str}: {e}")
            continue

        if not is_success(raw):
            continue
            
        orders = extract_orders(raw)
        
        for item in orders:
            order = item.get("Order", {})
            created_on_str = order.get("created_on", "")
            if not created_on_str:
                continue
                
            created_on = datetime.strptime(created_on_str, "%Y-%m-%d %H:%M:%S")
            
            # --- 4 AM BUFFER BUSINESS DAY LOGIC ---
            if created_on.hour < 4:
                business_date = (created_on - timedelta(days=1)).date()
            else:
                business_date = created_on.date()
                
            affected_business_dates.add(business_date)
            
            order_id = int(order.get("orderID", 0))
            total_amt = float(order.get("total", 0))
            
            # --- UPSERT: Individual Bill in PetpoojaOrder (Duplicate Blocking) ---
            stmt = _upsert(db, PetpoojaOrder).values(
                order_id=order_id,
                outlet_id=outlet.id,
                business_date=business_date,
                created_on=created_on,
                total_amount=total_amt
            ).on_conflict_do_update(
                index_elements=['order_id'],
                set_={'total_amount': total_amt}
            )
            db.execute(stmt)
            
    db.commit() # Individual bills safely database mein chale gaye

    # 2. DailySaleCache ko Re-calculate aur Upsert karna
    for b_date in affected_business_dates:
        stats = db.query(
            func.sum(PetpoojaOrder.total_amount).label("tot"),
            func.count(PetpoojaOrder.order_id).label("cnt")
        ).filter(
            PetpoojaOrder.outlet_id == outlet.id,
            PetpoojaOrder.business_date == b_date
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
            fetched_at=now
        ).on_conflict_do_update(
            index_elements=['outlet_id', 'sale_date'],
            set_={
                'total_sales': tot,
                'bill_count': cnt,
                'avg_bill': avg,
                'fetched_at': now
            }
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