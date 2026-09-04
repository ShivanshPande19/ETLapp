"""Adapter #2 — Petpooja ``get_sales_data`` (a.k.a. "flavour B").

Used by outlets mapped under a Petpooja integration account that only exposes
the `get_sales_data` endpoint (e.g. **Coffee Vault** ``r6h4cd0k2sfi``). Unlike
flavour A this endpoint:

* authenticates with **query params** (no ``Cookie`` header);
* returns a bill's ``Receipt Date`` + ``Transaction Time``. Petpooja's own
  SALES DASHBOARD closes the operational day at 03:00 — a bill rung between
  midnight and 02:59 belongs to the PREVIOUS day. We reproduce that here by
  shifting any bill whose ``Transaction Time`` hour is ``< 3`` back one day
  (:data:`SALESDATA_DAY_CUTOFF_HOUR`). This was pinned by reconciling this
  endpoint against the dashboard for Coffee Vault to the rupee across multiple
  days. (History: we first re-applied the court's attendance ``day_cutoff_hour``
  of 5 → over-shifted; then dropped the cutoff entirely and attributed by raw
  Receipt Date → matched the "yesterday sales" EMAIL but drifted a few hundred
  to ~1.3k off the DASHBOARD both ways. The dashboard's true boundary is 03:00,
  and it is intentionally SEPARATE from the court's attendance cutoff.);
* keys bills by a per-outlet sequential ``Receipt number`` (safe here because
  ``sales_orders`` is unique on ``(outlet_id, source, external_ref)``);
* reports the final amount in ``Net sale``;
* mixes in non-revenue rows — we keep only ``Transaction status == SALE`` **and**
  ``order_status == Success``.

Enabling Coffee Vault does NOT require any Petpooja remap: it uses this outlet's
OWN per-outlet credentials (``outlet.pp_app_key/pp_app_secret/pp_access_token``)
— the exact creds already proven to return this outlet's sales via
`get_sales_data`. Go-live is just data/config: store those creds on the outlet
row and set ``pos_source='petpooja_salesdata'``. (Day attribution uses this
source's own 03:00 cutoff — see :data:`SALESDATA_DAY_CUTOFF_HOUR` — NOT the
court's attendance ``day_cutoff_hour``.) See PROGRESS_MULTISOURCE.md, Phase 2.

The records array lives under the top-level ``"Records"`` key (confirmed against
a live response during investigation); :func:`_extract_records` keeps a few
fallbacks for safety.
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from typing import List

import httpx
import logging

from ...core.config import settings
from .base import NormalizedOrder, SalesSourceAdapter, register

logger = logging.getLogger("sales.petpooja_salesdata")

PETPOOJA_SALESDATA_URL = "https://api.petpooja.com/V1/orders/get_sales_data/"

# ── Business-day cutoff for this source ──────────────────────────────────────
# Petpooja's own SALES DASHBOARD closes the operational day at 03:00 (a bill
# rung between 00:00 and 02:59 counts toward the PREVIOUS day). This was pinned
# empirically by reconciling get_sales_data against the dashboard for Coffee
# Vault (Central 50) — with a 03:00 cutoff the app reproduced the dashboard's
# daily totals to the rupee across multiple days (Aug 23/24/25 2026: 77,296 /
# 24,032 / 34,946 — exact), whereas raw Receipt-Date and a 05:00 cutoff both
# disagreed.
#
# NOTE: this is DELIBERATELY independent of the court's ``day_cutoff_hour``
# (which drives attendance and is 5 for Central 50). Sales must follow the POS
# dashboard's day boundary, not the attendance one. Only outlets on this adapter
# (currently just Coffee Vault) are affected. If a future ``petpooja_salesdata``
# outlet uses a different dashboard day-start, this should become per-outlet
# config.
SALESDATA_DAY_CUTOFF_HOUR = 3

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


def _business_date_for(receipt_date: date, txn_time: str, cutoff_hour: int) -> date:
    """Attribute a bill to Petpooja's operational (dashboard) day.

    A bill whose ``Transaction Time`` hour is before ``cutoff_hour`` (i.e. rung
    in the small hours after midnight) belongs to the PREVIOUS operational day,
    matching how the Petpooja sales dashboard groups late-night bills. An
    unparseable time is treated as ``>= cutoff`` (no shift) so it stays on its
    own Receipt Date rather than silently moving.
    """
    if cutoff_hour and cutoff_hour > 0:
        hour = cutoff_hour  # default: unknown time → don't shift
        for fmt in ("%H:%M:%S", "%H:%M"):
            try:
                hour = datetime.strptime(txn_time.strip(), fmt).hour
                break
            except (ValueError, AttributeError):
                continue
        if hour < cutoff_hour:
            return receipt_date - timedelta(days=1)
    return receipt_date


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

    logger.info(f"[PETPOOJA SALESDATA START] rest_id={rest_id} {from_date} -> {to_date}")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.get(PETPOOJA_SALESDATA_URL, params=params)
        logger.info(f"[PETPOOJA SALESDATA HTTP] rest_id={rest_id} status_code={resp.status_code}")
        resp.raise_for_status()
        raw = resp.json()

    recs = _extract_records(raw)
    logger.info(
        f"[PETPOOJA SALESDATA SUCCESS] rest_id={rest_id} "
        f"success={raw.get('success')} code={raw.get('code')} rows={len(recs)}"
    )
    return raw


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
        # Over-fetch into the next morning UP TO — but not past — the cutoff, so
        # the latest requested day (`hi`) picks up its post-midnight bills (which
        # carry Receipt Date hi+1 but belong to business day hi). Stopping AT the
        # cutoff is deliberate: every over-fetched hi+1 bill has hour < cutoff and
        # is shifted back to hi, so no partial `hi+1` cache row is ever created
        # (bills at/after the cutoff — hi+1's real day — are simply not fetched).
        cutoff_dt = datetime.combine(hi + timedelta(days=1), time(SALESDATA_DAY_CUTOFF_HOUR, 0, 0))
        over_fetch_end = cutoff_dt - timedelta(seconds=1)
        from_date = f"{lo.strftime('%Y-%m-%d')} 00:00:00"
        to_date = over_fetch_end.strftime("%Y-%m-%d %H:%M:%S")

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
            logger.warning(f"[PETPOOJA SALESDATA ERROR] {outlet.rest_id} {from_date}->{to_date}: {e}")
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

            # Attribute to Petpooja's operational day using THIS source's own
            # 03:00 dashboard cutoff (not the court's attendance cutoff_hour).
            business_date = _business_date_for(
                receipt_date, txn_time, SALESDATA_DAY_CUTOFF_HOUR
            )

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

        logger.info(f"[PETPOOJA SALESDATA ATTRIBUTE] rest_id={outlet.rest_id} counted={len(normalized)}")
        return normalized


register(PetpoojaSalesDataAdapter())
