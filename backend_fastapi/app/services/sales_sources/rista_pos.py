"""Adapter #4 — Rista POS (https://api.ristaapps.com).

Rista exposes a per-day sales list at ``GET /v1/sales/summary`` scoped by branch.

Auth (verified against the live API):
    * generate a short JWT signed with the outlet's Secret Key (HS256) whose
      claims are ``{iss: <API Key>, iat: <now>, jti: <uuid>}``;
    * send it in the ``x-api-token`` header alongside ``x-api-key: <API Key>``.

Per-outlet credentials are stored on the ``Outlet`` row (same columns the other
adapters reuse), so nothing secret lives in the code:
    * ``rest_id``       → Rista **branch code** (e.g. "GNO")
    * ``pp_app_key``    → Rista **API Key**
    * ``pp_app_secret`` → Rista **Secret Key**
    * ``pos_source``    → "rista"

Response shape (one invoice per element under ``data``; ``lastKey`` paginates):
    invoiceNumber, invoiceDate (ISO, +05:30), invoiceType ("Sale"/"Return"/…),
    status ("Closed"/…), netAmount (ex-tax), taxAmount, totalAmount (incl-tax),
    channel, …

We count only ``invoiceType == "Sale"`` bills (returns/refunds excluded) whose
status isn't void/cancelled, and use ``totalAmount`` (the full settled bill,
incl tax — consistent with the Petpooja adapters' bill totals) as the amount.
Attribution is by the queried calendar ``day`` (Rista groups by it), so a day's
total reconciles exactly with Rista's own day report; ``cutoff_hour`` is not
applied here (mirrors the Petpooja sales_data adapter).
"""

from __future__ import annotations

import logging
import time
import uuid
from datetime import date, datetime
from typing import List

import httpx
from jose import jwt as _jwt

from .base import NormalizedOrder, SalesSourceAdapter, register

logger = logging.getLogger("sales.rista")

RISTA_BASE = "https://api.ristaapps.com"
RISTA_SALES_SUMMARY = "/v1/sales/summary"

# Bills that must NOT count toward revenue.
_NON_SALE_STATUS = {"void", "voided", "cancelled", "canceled", "deleted"}
# Hard cap on pages per day (50 invoices/page) — a safety valve against an
# unexpected pagination loop; ~10k invoices/day is far beyond any real outlet.
_MAX_PAGES = 200


def _auth_headers(api_key: str, secret: str) -> dict:
    """A fresh signed request token. Rista wants a JWT (HS256) signed with the
    Secret Key, plus the API key in its own header."""
    now = int(time.time())
    token = _jwt.encode(
        {"iss": api_key, "iat": now, "jti": uuid.uuid4().hex},
        secret,
        algorithm="HS256",
    )
    return {"x-api-key": api_key, "x-api-token": token, "Content-Type": "application/json"}


async def _fetch_day(
    client: httpx.AsyncClient,
    api_key: str,
    secret: str,
    branch: str,
    day_str: str,
) -> List[dict]:
    """Every invoice for one branch+day, following ``lastKey`` pagination."""
    records: List[dict] = []
    last_key: str | None = None
    for _ in range(_MAX_PAGES):
        params = {"branch": branch, "day": day_str}
        if last_key:
            params["lastKey"] = last_key
        # Fresh token per request (they're short-lived / single-use by design).
        resp = await client.get(
            RISTA_BASE + RISTA_SALES_SUMMARY,
            headers=_auth_headers(api_key, secret),
            params=params,
        )
        resp.raise_for_status()
        payload = resp.json()
        page = payload.get("data") or []
        records.extend(page)
        last_key = payload.get("lastKey")
        if not last_key or not page:
            break
    return records


class RistaPosAdapter(SalesSourceAdapter):
    source_key = "rista"

    async def fetch_normalized_orders(
        self,
        outlet,
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,  # not applied — Rista groups by calendar day
    ) -> List[NormalizedOrder]:
        if not api_fetch_dates:
            return []

        api_key = (outlet.pp_app_key or "").strip()
        secret = (outlet.pp_app_secret or "").strip()
        branch = (outlet.rest_id or "").strip()
        if not (api_key and secret and branch):
            logger.warning(
                "[RISTA] outlet=%s missing credentials (need rest_id=branch, "
                "pp_app_key=API key, pp_app_secret=secret)", outlet.id
            )
            return []

        normalized: List[NormalizedOrder] = []
        async with httpx.AsyncClient(timeout=40.0) as client:
            for d in sorted(set(api_fetch_dates)):
                day_str = d.strftime("%Y-%m-%d")
                try:
                    records = await _fetch_day(client, api_key, secret, branch, day_str)
                except Exception as e:
                    logger.warning("[RISTA] fetch failed outlet=%s day=%s: %s", outlet.id, day_str, e)
                    continue

                logger.info("[RISTA] outlet=%s day=%s invoices=%d", outlet.id, day_str, len(records))

                for rec in records:
                    if str(rec.get("invoiceType", "")).strip().lower() != "sale":
                        continue
                    if str(rec.get("status", "")).strip().lower() in _NON_SALE_STATUS:
                        continue
                    inv = str(rec.get("invoiceNumber", "") or "").strip()
                    if not inv:
                        continue

                    try:
                        amount = float(rec.get("totalAmount") or 0)
                    except (ValueError, TypeError):
                        amount = 0.0

                    # created_on from the ISO invoiceDate (+05:30); store naive
                    # IST. business_date is the queried day so the day total
                    # reconciles with Rista's own report.
                    created_on = datetime.combine(d, datetime.min.time())
                    iso = str(rec.get("invoiceDate", "") or "").strip()
                    if iso:
                        try:
                            created_on = datetime.fromisoformat(iso).replace(tzinfo=None)
                        except ValueError:
                            pass

                    normalized.append(
                        NormalizedOrder(
                            external_ref=inv,
                            business_date=d,
                            created_on=created_on,
                            total_amount=amount,
                            status=str(rec.get("status", "") or "Closed"),
                        )
                    )

        logger.info("[RISTA] outlet=%s counted=%d", outlet.id, len(normalized))
        return normalized


register(RistaPosAdapter())
