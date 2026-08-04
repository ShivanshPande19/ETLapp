"""Adapter #2 — Petpooja ``get_sales_data`` (a.k.a. "flavour B").

Used by outlets mapped under a Petpooja integration account that only exposes
the `get_sales_data` endpoint (e.g. **Coffee Vault** ``r6h4cd0k2sfi``). Unlike
flavour A this endpoint:

* authenticates with **query params** (no ``Cookie`` header);
* returns a bill's **calendar** ``Receipt Date`` + ``Transaction Time`` (it does
  NOT pre-group post-midnight bills), so we apply the court's
  ``day_cutoff_hour`` ourselves — a bill whose time-of-day hour is ``< cutoff``
  belongs to the previous operational day. This fixes "raat ke bills galat din";
* keys bills by a per-outlet sequential ``Receipt number`` (safe here because
  ``sales_orders`` is unique on ``(outlet_id, source, external_ref)``);
* reports the final amount in ``Net sale``;
* mixes in non-revenue rows — we keep only ``Transaction status == SALE`` **and**
  ``order_status == Success``.

Enabling Coffee Vault does NOT require any Petpooja remap: it uses this outlet's
OWN per-outlet credentials (``outlet.pp_app_key/pp_app_secret/pp_access_token``)
— the exact creds already proven to return this outlet's sales via
`get_sales_data`. Go-live is just data/config: store those creds on the outlet
row, set ``pos_source='petpooja_salesdata'``, and set the court's
``day_cutoff_hour`` (~5-6). See PROGRESS_MULTISOURCE.md, Phase 2.

The records array lives under the top-level ``"Records"`` key (confirmed against
a live response during investigation); :func:`_extract_records` keeps a few
fallbacks for safety.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import List

import httpx

from ...core.config import settings
from .base import NormalizedOrder, SalesSourceAdapter, register

PETPOOJA_SALESDATA_URL = "https://api.petpooja.com/V1/orders/get_sales_data/"

# "Records" is the confirmed live key (verified against a real get_sales_data
# response). The rest are defensive fallbacks only.
_RECORD_KEYS = ("Records", "records", "data", "sales_data", "order_json", "sales")


def _extract_records(raw: dict) -> list:
    if isinstance(raw, list):
        return raw
    for key in _RECORD_KEYS:
        val = raw.get(key)
        if isinstance(val, list):
            return val
    return []


def _is_success(raw: dict) -> bool:
    return str(raw.get("success")) == "1" or str(raw.get("code")) in ("200", "1")


def _is_revenue_row(rec: dict) -> bool:
    return (
        str(rec.get("Transaction status", "")).strip().upper() == "SALE"
        and str(rec.get("order_status", "")).strip().lower() == "success"
    )


async def fetch_raw(
    rest_id: str,
    from_date: str,
    to_date: str,
    app_key: str | None = None,
    app_secret: str | None = None,
    access_token: str | None = None,
) -> dict:
    """Fetch the sales_data range. Auth is via query params (no cookie)."""
    params = {
        "app_key": app_key or settings.PETPOOJA_APP_KEY,
        "app_secret": app_secret or settings.PETPOOJA_APP_SECRET,
        "access_token": access_token or settings.PETPOOJA_ACCESS_TOKEN,
        "restID": rest_id,
        "from_date": from_date,
        "to_date": to_date,
    }

    print(f"[PETPOOJA SALESDATA START] rest_id={rest_id} {from_date} -> {to_date}")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(PETPOOJA_SALESDATA_URL, params=params)
        print(f"[PETPOOJA SALESDATA HTTP] rest_id={rest_id} status_code={resp.status_code}")
        resp.raise_for_status()
        raw = resp.json()

    recs = _extract_records(raw)
    print(
        f"[PETPOOJA SALESDATA SUCCESS] rest_id={rest_id} "
        f"success={raw.get('success')} code={raw.get('code')} rows={len(recs)}"
    )
    return raw


def _business_date_for(receipt_date: date, txn_time: str, cutoff_hour: int) -> date:
    """Shift a calendar receipt date to the previous operational day when the
    bill's hour-of-day falls before the court's overnight cutoff."""
    if cutoff_hour and cutoff_hour > 0:
        hour = 0
        try:
            hour = datetime.strptime(txn_time.strip(), "%H:%M:%S").hour
        except (ValueError, AttributeError):
            try:
                hour = datetime.strptime(txn_time.strip(), "%H:%M").hour
            except (ValueError, AttributeError):
                hour = cutoff_hour  # unknown time → don't shift
        if hour < cutoff_hour:
            return receipt_date - timedelta(days=1)
    return receipt_date


class PetpoojaSalesDataAdapter(SalesSourceAdapter):
    source_key = "petpooja_salesdata"

    async def fetch_normalized_orders(
        self,
        outlet,
        api_fetch_dates: List[date],
        cutoff_hour: int = 0,
    ) -> List[NormalizedOrder]:
        if not api_fetch_dates:
            return []

        lo = min(api_fetch_dates)
        hi = max(api_fetch_dates)
        # Over-fetch into the next morning so post-midnight bills that belong to
        # `hi` (once the cutoff is applied) are included. Composite upsert makes
        # any slight over-fetch harmless (idempotent).
        from_date = f"{lo.strftime('%Y-%m-%d')} 00:00:00"
        to_date = f"{(hi + timedelta(days=1)).strftime('%Y-%m-%d')} 06:00:00"

        try:
            raw = await fetch_raw(
                outlet.rest_id,
                from_date,
                to_date,
                app_key=outlet.pp_app_key,
                app_secret=outlet.pp_app_secret,
                access_token=outlet.pp_access_token,
            )
        except Exception as e:
            print(f"[PETPOOJA SALESDATA ERROR] {outlet.rest_id} {from_date}->{to_date}: {e}")
            return []

        if not _is_success(raw):
            return []

        normalized: List[NormalizedOrder] = []
        for rec in _extract_records(raw):
            if not _is_revenue_row(rec):
                continue

            receipt_no = str(rec.get("Receipt number", "") or "").strip()
            if not receipt_no:
                continue

            try:
                total_amt = float(rec.get("Net sale", 0) or 0)
            except (ValueError, TypeError):
                total_amt = 0.0

            receipt_date_str = str(rec.get("Receipt Date", "") or "").strip()
            txn_time = str(rec.get("Transaction Time", "") or "").strip()
            try:
                receipt_date = datetime.strptime(receipt_date_str, "%Y-%m-%d").date()
            except ValueError:
                continue  # cannot attribute without a date

            business_date = _business_date_for(receipt_date, txn_time, cutoff_hour)

            try:
                created_on = datetime.strptime(
                    f"{receipt_date_str} {txn_time}", "%Y-%m-%d %H:%M:%S"
                )
            except ValueError:
                created_on = datetime.combine(business_date, datetime.min.time())

            normalized.append(
                NormalizedOrder(
                    external_ref=receipt_no,
                    business_date=business_date,
                    created_on=created_on,
                    total_amount=total_amt,
                    status="Success",
                )
            )

        print(f"[PETPOOJA SALESDATA ATTRIBUTE] rest_id={outlet.rest_id} counted={len(normalized)}")
        return normalized


register(PetpoojaSalesDataAdapter())
