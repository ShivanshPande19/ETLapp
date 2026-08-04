"""Adapter #1 — Petpooja ``generic_get_orders`` (a.k.a. "flavour A").

This is the flow The Momo Box already runs on, moved verbatim behind the adapter
interface. Behaviour is intentionally **identical** to the pre-refactor
``petpooja_service`` code:

* auth via JSON body + ``Cookie: PETPOOJA_API=<cookie>``;
* per-outlet creds with fallback to global settings;
* business day taken from each bill's own ``order_date`` field (Petpooja already
  files post-midnight bills under the previous operational day), falling back to
  the documented ``requested_date - 1`` rule only when that field is missing;
* every order with a valid ``orderID`` counts (no status filtering — matches the
  original behaviour, so backfilled totals reconcile exactly).
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import List

import httpx

from ...core.config import settings
from .base import NormalizedOrder, SalesSourceAdapter, register

PETPOOJA_URL = "https://api.petpooja.com/V1/thirdparty/generic_get_orders/"


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


class PetpoojaGenericAdapter(SalesSourceAdapter):
    source_key = "petpooja_generic"

    async def fetch_normalized_orders(
        self,
        outlet,
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,  # ignored — Petpooja already reports the operational day
    ) -> List[NormalizedOrder]:
        normalized: List[NormalizedOrder] = []

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
            attributed = 0

            for item in orders:
                order = item.get("Order", {})

                try:
                    order_id = int(order.get("orderID", 0))
                except (ValueError, TypeError):
                    order_id = 0
                if order_id <= 0:
                    continue

                try:
                    total_amt = float(order.get("total", 0) or 0)
                except (ValueError, TypeError):
                    total_amt = 0.0

                # Business day = Petpooja's own per-order `order_date`. Petpooja
                # already groups post-midnight bills under the PREVIOUS day here
                # (verified: a bill at "…01:05:40" carries order_date of the
                # prior calendar day). Fallback to the documented T-1 rule only
                # when the field is missing/unparseable.
                order_date_str = order.get("order_date", "") or ""
                try:
                    business_date = datetime.strptime(order_date_str, "%Y-%m-%d").date()
                except ValueError:
                    business_date = api_date - timedelta(days=1)

                created_on_str = order.get("created_on", "") or ""
                try:
                    created_on = datetime.strptime(created_on_str, "%Y-%m-%d %H:%M:%S")
                except ValueError:
                    created_on = datetime.combine(business_date, datetime.min.time())

                normalized.append(
                    NormalizedOrder(
                        external_ref=str(order_id),
                        business_date=business_date,
                        created_on=created_on,
                        total_amount=total_amt,
                        status="completed",
                    )
                )
                attributed += 1

            print(f"[ATTRIBUTE] request_order_date={api_date_str} | bills={attributed}")

        return normalized


register(PetpoojaGenericAdapter())
