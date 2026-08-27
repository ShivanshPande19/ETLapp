"""petpooja_salesdata must attribute bills by Petpooja's Receipt Date — NOT by
re-applying the court's overnight cutoff (which double-shifted post-midnight
bills and broke reconciliation with the Petpooja email — Coffee Vault bug)."""
import asyncio
import datetime as dt

from app.services.sales_sources import petpooja_salesdata as sd


class _Outlet:
    id = 2
    rest_id = "r6h4cd0k2sfi"
    pp_app_key = None
    pp_app_secret = None
    pp_access_token = None


def _run(outlet, dates, cutoff):
    adapter = sd.PetpoojaSalesDataAdapter()
    return asyncio.run(
        adapter.fetch_normalized_orders(outlet, dates, cutoff_hour=cutoff)
    )


def _totals_by_date(orders):
    out = {}
    for o in orders:
        out[o.business_date] = round(out.get(o.business_date, 0.0) + o.total_amount, 2)
    return out


def test_post_midnight_bill_stays_on_its_receipt_date(monkeypatch):
    async def fake_fetch_raw(*a, **k):
        return {
            "success": "1",
            "Records": [
                # 02:30 AM bill on the 24th — must NOT move to the 23rd even
                # though cutoff_hour=5 is passed.
                {"Receipt number": "R1", "Net sale": "100",
                 "Receipt Date": "2026-08-24", "Transaction Time": "02:30:00",
                 "Transaction status": "SALE", "order_status": "success"},
                {"Receipt number": "R2", "Net sale": "200",
                 "Receipt Date": "2026-08-24", "Transaction Time": "14:00:00",
                 "Transaction status": "SALE", "order_status": "success"},
            ],
        }

    monkeypatch.setattr(sd, "fetch_raw", fake_fetch_raw)
    orders = _run(_Outlet(), [dt.date(2026, 8, 24)], cutoff=5)
    # Both bills belong to the 24th (Receipt Date) — cutoff ignored.
    assert _totals_by_date(orders) == {dt.date(2026, 8, 24): 300.0}


def test_only_successful_sale_rows_counted(monkeypatch):
    async def fake_fetch_raw(*a, **k):
        return {
            "success": "1",
            "Records": [
                {"Receipt number": "R1", "Net sale": "100",
                 "Receipt Date": "2026-08-24", "Transaction Time": "10:00:00",
                 "Transaction status": "SALE", "order_status": "success"},
                # cancelled / non-revenue rows must be excluded
                {"Receipt number": "R2", "Net sale": "999",
                 "Receipt Date": "2026-08-24", "Transaction Time": "11:00:00",
                 "Transaction status": "CANCEL", "order_status": "success"},
                {"Receipt number": "R3", "Net sale": "999",
                 "Receipt Date": "2026-08-24", "Transaction Time": "12:00:00",
                 "Transaction status": "SALE", "order_status": "failed"},
            ],
        }

    monkeypatch.setattr(sd, "fetch_raw", fake_fetch_raw)
    orders = _run(_Outlet(), [dt.date(2026, 8, 24)], cutoff=5)
    assert _totals_by_date(orders) == {dt.date(2026, 8, 24): 100.0}
