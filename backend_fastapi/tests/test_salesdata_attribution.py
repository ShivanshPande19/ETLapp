"""petpooja_salesdata attributes bills to Petpooja's SALES-DASHBOARD operational
day, which closes at 03:00 (SALESDATA_DAY_CUTOFF_HOUR): a bill rung between
midnight and 02:59 belongs to the PREVIOUS day. This 03:00 boundary was pinned
by reconciling get_sales_data against the Coffee Vault dashboard to the rupee,
and is deliberately SEPARATE from the court's attendance day_cutoff_hour."""
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


def test_pre_cutoff_bill_moves_to_previous_day(monkeypatch):
    async def fake_fetch_raw(*a, **k):
        return {
            "success": "1",
            "Records": [
                # 02:30 AM bill on the 24th — before the 03:00 dashboard cutoff,
                # so it counts toward the 23rd.
                {"Receipt number": "R1", "Net sale": "100",
                 "Receipt Date": "2026-08-24", "Transaction Time": "02:30:00",
                 "Transaction status": "SALE", "order_status": "success"},
                # 14:00 bill on the 24th — stays on the 24th.
                {"Receipt number": "R2", "Net sale": "200",
                 "Receipt Date": "2026-08-24", "Transaction Time": "14:00:00",
                 "Transaction status": "SALE", "order_status": "success"},
            ],
        }

    monkeypatch.setattr(sd, "fetch_raw", fake_fetch_raw)
    orders = _run(_Outlet(), [dt.date(2026, 8, 24)], cutoff=5)
    assert _totals_by_date(orders) == {
        dt.date(2026, 8, 23): 100.0,
        dt.date(2026, 8, 24): 200.0,
    }


def test_bill_at_cutoff_hour_stays_on_its_day(monkeypatch):
    async def fake_fetch_raw(*a, **k):
        return {
            "success": "1",
            "Records": [
                # exactly 03:00:00 — at the cutoff, so it belongs to its own day.
                {"Receipt number": "R1", "Net sale": "150",
                 "Receipt Date": "2026-08-24", "Transaction Time": "03:00:00",
                 "Transaction status": "SALE", "order_status": "success"},
                # 02:59:59 — one second before the cutoff, moves to the 23rd.
                {"Receipt number": "R2", "Net sale": "150",
                 "Receipt Date": "2026-08-24", "Transaction Time": "02:59:59",
                 "Transaction status": "SALE", "order_status": "success"},
            ],
        }

    monkeypatch.setattr(sd, "fetch_raw", fake_fetch_raw)
    orders = _run(_Outlet(), [dt.date(2026, 8, 24)], cutoff=0)
    assert _totals_by_date(orders) == {
        dt.date(2026, 8, 23): 150.0,
        dt.date(2026, 8, 24): 150.0,
    }


def test_cutoff_is_independent_of_court_day_cutoff_hour(monkeypatch):
    """The court's attendance cutoff (passed as cutoff_hour) must NOT change
    sales attribution — this source always uses its own 03:00 boundary."""
    async def fake_fetch_raw(*a, **k):
        return {
            "success": "1",
            "Records": [
                # 04:00 bill — after the 03:00 sales cutoff, so it stays on the
                # 24th even though the court's attendance cutoff of 5 would have
                # (wrongly) pushed it to the 23rd.
                {"Receipt number": "R1", "Net sale": "500",
                 "Receipt Date": "2026-08-24", "Transaction Time": "04:00:00",
                 "Transaction status": "SALE", "order_status": "success"},
            ],
        }

    monkeypatch.setattr(sd, "fetch_raw", fake_fetch_raw)
    orders = _run(_Outlet(), [dt.date(2026, 8, 24)], cutoff=5)
    assert _totals_by_date(orders) == {dt.date(2026, 8, 24): 500.0}


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
