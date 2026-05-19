import json
from datetime import date, timedelta, datetime

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from ..core.config import settings
from ..models.sale import Outlet, DailySaleCache, Court

PETPOOJA_URL = "https://api.petpooja.com/V1/thirdparty/generic_get_orders/"


async def fetch_raw(rest_id: str, order_date: str) -> dict:
    payload = {
        "app_key": settings.PETPOOJA_APP_KEY,
        "app_secret": settings.PETPOOJA_APP_SECRET,
        "access_token": settings.PETPOOJA_ACCESS_TOKEN,
        "restID": rest_id,
        "order_date": order_date,
        "refId": "",
    }

    headers = {
        "Content-Type": "application/json",
        "Cookie": f"PETPOOJA_API={settings.PETPOOJA_COOKIE}",
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


def summarise_raw(raw: dict) -> dict:
    orders = extract_orders(raw)

    if not orders:
        return {
            "total_sales": 0.0,
            "bill_count": 0,
            "avg_bill": 0.0,
        }

    total = 0.0
    for order in orders:
        try:
            total += float(order.get("Order", {}).get("total", 0) or 0)
        except Exception:
            continue

    count = len(orders)
    return {
        "total_sales": round(total, 2),
        "bill_count": count,
        "avg_bill": round(total / count, 2) if count else 0.0,
    }


async def sync_outlet_for_date(
    db: Session,
    outlet: Outlet,
    target_business_date: date,
    api_fetch_date: date,
    force_refresh: bool = False,
) -> DailySaleCache:
    
    api_date_str = api_fetch_date.strftime("%Y-%m-%d")
    
    existing = db.query(DailySaleCache).filter(
        DailySaleCache.outlet_id == outlet.id,
        DailySaleCache.sale_date == target_business_date,
    ).first()

    if existing and not force_refresh:
        print(
            f"[CACHE HIT] vendor={outlet.vendor_name} rest_id={outlet.rest_id} "
            f"sale_date={target_business_date} total_sales={existing.total_sales}"
        )
        return existing

    print(
        f"[CACHE {'REFRESH' if existing else 'MISS'}] vendor={outlet.vendor_name} "
        f"business_date={target_business_date} petpooja_api_date={api_date_str}"
    )

    raw = await fetch_raw(outlet.rest_id, api_date_str)

    if not is_success(raw):
        print(f"[PETPOOJA ERROR] Failed for {outlet.rest_id}. Response: {raw}")
        if existing:
            return existing
        return None

    summary = summarise_raw(raw)
    now = datetime.utcnow()

    # SQLite Native UPSERT (Insert or Update if exists based on unique index)
    stmt = sqlite_insert(DailySaleCache).values(
        outlet_id=outlet.id,
        sale_date=target_business_date,
        total_sales=summary["total_sales"],
        bill_count=summary["bill_count"],
        avg_bill=summary["avg_bill"],
        raw_json=json.dumps(raw),
        fetched_at=now
    ).on_conflict_do_update(
        index_elements=['outlet_id', 'sale_date'],
        set_={
            'total_sales': summary["total_sales"],
            'bill_count': summary["bill_count"],
            'avg_bill': summary["avg_bill"],
            'raw_json': json.dumps(raw),
            'fetched_at': now
        }
    )

    db.execute(stmt)
    db.commit()

    cache = db.query(DailySaleCache).filter_by(
        outlet_id=outlet.id, sale_date=target_business_date
    ).first()

    print(
        f"[CACHE SAVED] vendor={outlet.vendor_name} "
        f"sale_date={cache.sale_date} total_sales={cache.total_sales}"
    )
    return cache


# === ROUTE HANDLERS === 

async def sync_court_by_fetch_date(
    db: Session,
    court_uid: str,
    fetch_for_date: date,
    force_refresh: bool = True,
) -> dict:
    """ Ye function `sales.py` route se single court sync karne ke liye use hota hai """
    business_date = fetch_for_date - timedelta(days=1)

    court = db.query(Court).filter(
        Court.court_uid == court_uid,
        Court.is_active == 1,
    ).first()
    if not court:
        raise ValueError("Court not found")

    outlets = db.query(Outlet).filter(
        Outlet.court_id == court.id,
        Outlet.is_active == 1,
    ).all()

    results = []
    for outlet in outlets:
        cache = await sync_outlet_for_date(
            db=db,
            outlet=outlet,
            target_business_date=business_date,
            api_fetch_date=fetch_for_date,
            force_refresh=force_refresh,
        )
        if cache:
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "rest_id": outlet.rest_id,
                "court_id": outlet.court_id,
                "fetch_for_date": str(fetch_for_date),
                "business_date": str(business_date),
                "petpooja_api_date": str(fetch_for_date),
                "sale_date": str(cache.sale_date),
                "total_sales": cache.total_sales,
                "bill_count": cache.bill_count,
                "avg_bill": cache.avg_bill,
                "fetched_at": str(cache.fetched_at),
            })

    return {
        "court_uid": court.court_uid,
        "court_name": court.name,
        "fetch_for_date": str(fetch_for_date),
        "business_date": str(business_date),
        "petpooja_api_date": str(fetch_for_date),
        "outlets_synced": len(results),
        "results": results,
    }


async def sync_all_active_outlets_by_fetch_date(
    db: Session,
    fetch_for_date: date,
    force_refresh: bool = True,
) -> dict:
    """ Ye function Cron Job aur "Sync All" route ke liye use hota hai """
    business_date = fetch_for_date - timedelta(days=1)
    outlets = db.query(Outlet).filter(Outlet.is_active == 1).all()

    results = []
    for outlet in outlets:
        cache = await sync_outlet_for_date(
            db=db,
            outlet=outlet,
            target_business_date=business_date,
            api_fetch_date=fetch_for_date,
            force_refresh=force_refresh,
        )
        if cache:
            results.append({
                "outlet_id": outlet.id,
                "vendor_name": outlet.vendor_name,
                "rest_id": outlet.rest_id,
                "court_id": outlet.court_id,
                "fetch_for_date": str(fetch_for_date),
                "business_date": str(business_date),
                "petpooja_api_date": str(fetch_for_date),
                "sale_date": str(cache.sale_date),
                "total_sales": cache.total_sales,
                "bill_count": cache.bill_count,
                "avg_bill": cache.avg_bill,
                "fetched_at": str(cache.fetched_at),
            })

    return {
        "fetch_for_date": str(fetch_for_date),
        "business_date": str(business_date),
        "petpooja_api_date": str(fetch_for_date),
        "outlets_synced": len(results),
        "results": results,
    }