"""Adapter #3 — Royal POS (get_completed_orders_item_wise_dynamic)."""

from __future__ import annotations

from datetime import date, datetime
from typing import List

import httpx

from .base import NormalizedOrder, SalesSourceAdapter, register

ROYAL_POS_URL = (
    "https://royalpos.in/royalpos/public/get_completed_orders_item_wise_dynamic"
)

async def fetch_raw(
    restaurant_id: str,
    brand_id: str,
    start_date: str,
    end_date: str,
) -> list:
    data = {
        "restaurant_id": restaurant_id,
        "brand_id": brand_id or "",
        "start_date": start_date,
        "end_date": end_date,
    }
    print(f"[ROYALPOS START] restaurant_id={restaurant_id} {start_date} -> {end_date}")
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(ROYAL_POS_URL, data=data)
        print(f"[ROYALPOS HTTP] restaurant_id={restaurant_id} status={resp.status_code}")
        resp.raise_for_status()
        raw = resp.json()
    if not isinstance(raw, list):
        print(f"[ROYALPOS WARN] non-list response: {str(raw)[:200]}")
        return []
    print(f"[ROYALPOS SUCCESS] restaurant_id={restaurant_id} records={len(raw)}")
    return raw

def _is_sale(rec: dict) -> bool:
    return str(rec.get("STATUS", "")).strip().upper() == "SALES"

class RoyalPosAdapter(SalesSourceAdapter):
    source_key = "royal_pos"

    async def fetch_normalized_orders(
        self,
        outlet,
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,  # ignored — Royal POS already reports BUSINESS_DT
    ) -> List[NormalizedOrder]:
        if not api_fetch_dates:
            return []

        lo = min(api_fetch_dates).strftime("%Y-%m-%d")
        hi = max(api_fetch_dates).strftime("%Y-%m-%d")

        try:
            records = await fetch_raw(
                restaurant_id=str(outlet.rest_id),
                brand_id=(outlet.pp_app_key or ""),
                start_date=lo,
                end_date=hi,
            )
        except Exception as e:
            print(f"[ROYALPOS ERROR] {outlet.rest_id} {lo}->{hi}: {e}")
            return []

        normalized: List[NormalizedOrder] = []
        for rec in records:
            if not _is_sale(rec):
                continue

            receipt_no = str(rec.get("RCPT_NUM", "") or "").strip()
            if not receipt_no:
                continue

            try:
                total_amt = float(rec.get("INV_AMT", 0) or 0)
            except (ValueError, TypeError):
                total_amt = 0.0

            biz_str = str(rec.get("BUSINESS_DT", "") or "").strip()
            rcpt_dt = str(rec.get("RCPT_DT", "") or "").strip()
            try:
                business_date = datetime.strptime(biz_str, "%Y-%m-%d").date()
            except ValueError:
                try:
                    business_date = datetime.strptime(rcpt_dt, "%Y%m%d").date()
                except ValueError:
                    continue

            rcpt_tm = str(rec.get("RCPT_TM", "") or "").strip().zfill(6)
            try:
                created_on = datetime.strptime(f"{rcpt_dt}{rcpt_tm}", "%Y%m%d%H%M%S")
            except ValueError:
                created_on = datetime.combine(business_date, datetime.min.time())

            normalized.append(
                NormalizedOrder(
                    external_ref=receipt_no,
                    business_date=business_date,
                    created_on=created_on,
                    total_amount=total_amt,
                    status="SALES",
                )
            )

        print(f"[ROYALPOS ATTRIBUTE] restaurant_id={outlet.rest_id} counted={len(normalized)}")
        return normalized

register(RoyalPosAdapter())
