from ..schemas.sale import SalesSummaryResponse, VendorSaleDetail, VendorHistoryResponse, DailySnapshot
from datetime import date, timedelta
from typing import Optional

COURT_SALES = {
    1: {
        "vendors": [
            VendorSaleDetail(vendor_name="Burger Hub",    source_system="GoFrugal", total_sales=18200.00, bill_count=52, avg_bill_value=350.00,  last_synced="2026-04-15T14:00:00"),
            VendorSaleDetail(vendor_name="Pizza Point",   source_system="Posist",   total_sales=16300.00, bill_count=41, avg_bill_value=397.56,  last_synced="2026-04-15T13:55:00"),
            VendorSaleDetail(vendor_name="Chai Corner",   source_system="Vyapar",   total_sales=8150.00,  bill_count=28, avg_bill_value=291.07,  last_synced="2026-04-15T13:50:00"),
            VendorSaleDetail(vendor_name="Rolls Station", source_system="Manual",   total_sales=6100.00,  bill_count=13, avg_bill_value=469.23,  last_synced="2026-04-15T12:00:00"),
        ]
    },
    2: {
        "vendors": [
            VendorSaleDetail(vendor_name="Dosa House",    source_system="GoFrugal", total_sales=14500.00, bill_count=48, avg_bill_value=302.08,  last_synced="2026-04-15T14:00:00"),
            VendorSaleDetail(vendor_name="Noodle Box",    source_system="Posist",   total_sales=11200.00, bill_count=35, avg_bill_value=320.00,  last_synced="2026-04-15T13:45:00"),
            VendorSaleDetail(vendor_name="Shake Hub",     source_system="Vyapar",   total_sales=7800.00,  bill_count=22, avg_bill_value=354.54,  last_synced="2026-04-15T13:30:00"),
        ]
    },
    3: {
        "vendors": [
            VendorSaleDetail(vendor_name="Biryani Bros",  source_system="Posist",   total_sales=21000.00, bill_count=61, avg_bill_value=344.26,  last_synced="2026-04-15T14:00:00"),
            VendorSaleDetail(vendor_name="Wrap & Roll",   source_system="GoFrugal", total_sales=9400.00,  bill_count=30, avg_bill_value=313.33,  last_synced="2026-04-15T13:50:00"),
            VendorSaleDetail(vendor_name="Cold Sips",     source_system="Manual",   total_sales=4350.00,  bill_count=18, avg_bill_value=241.66,  last_synced="2026-04-15T12:30:00"),
        ]
    },
}

# Multipliers per period so numbers feel realistic
PERIOD_MULTIPLIERS = {
    "yesterday": 1.0,
    "week":      6.8,
    "month":     28.5,
    "year":      340.0,
    "custom":    1.0,
}

def _date_label(period: str, date_from: Optional[str], date_to: Optional[str]) -> str:
    today = date.today()
    if period == "yesterday":
        return str(today - timedelta(days=1))
    elif period == "week":
        monday = today - timedelta(days=today.weekday())
        return f"{monday.strftime('%b %d')} – {today.strftime('%b %d')}"
    elif period == "month":
        return today.strftime("%B %Y")
    elif period == "year":
        return str(today.year)
    elif period == "custom" and date_from and date_to:
        return f"{date_from} – {date_to}"
    return str(today)


def get_sales_summary(
    court_id:  Optional[int] = None,
    period:    str           = "yesterday",
    date_from: Optional[str] = None,
    date_to:   Optional[str] = None,
) -> SalesSummaryResponse:

    if court_id and court_id in COURT_SALES:
        vendors = COURT_SALES[court_id]["vendors"]
    else:
        vendors = []
        for court_data in COURT_SALES.values():
            vendors.extend(court_data["vendors"])

    multiplier  = PERIOD_MULTIPLIERS.get(period, 1.0)
    scaled      = [
        VendorSaleDetail(
            vendor_name    = v.vendor_name,
            source_system  = v.source_system,
            total_sales    = round(v.total_sales * multiplier, 2),
            bill_count     = int(v.bill_count * multiplier),
            avg_bill_value = v.avg_bill_value,
            last_synced    = v.last_synced,
        )
        for v in vendors
    ]

    total_sales = sum(v.total_sales for v in scaled)
    total_bills = sum(v.bill_count  for v in scaled)

    return SalesSummaryResponse(
        date           = _date_label(period, date_from, date_to),
        period         = period,
        total_sales    = total_sales,
        total_bills    = total_bills,
        avg_bill_value = round(total_sales / total_bills, 2) if total_bills else 0,
        vendors        = scaled,
    )


def get_vendor_history(vendor_name: str, court_id: int) -> VendorHistoryResponse:
    vendors = COURT_SALES.get(court_id, {}).get("vendors", [])
    vendor  = next((v for v in vendors if v.vendor_name == vendor_name), None)

    if vendor is None:
        # fallback: search all courts
        for court_data in COURT_SALES.values():
            vendor = next((v for v in court_data["vendors"] if v.vendor_name == vendor_name), None)
            if vendor:
                break

    if vendor is None:
        raise ValueError(f"Vendor '{vendor_name}' not found")

    today      = date.today()
    base_daily = vendor.total_sales
    history    = []
    best_sales = 0.0
    best_day   = str(today)

    for i in range(7, 0, -1):
        day        = today - timedelta(days=i)
        import random, hashlib
        seed       = int(hashlib.md5(f"{vendor_name}{day}".encode()).hexdigest(), 16) % 1000
        random.seed(seed)
        factor     = 0.6 + random.random() * 0.8
        sales      = round(base_daily * factor, 2)
        bills      = max(1, int(vendor.bill_count * factor))
        snap       = DailySnapshot(date=str(day), total_sales=sales, total_bills=bills)
        history.append(snap)
        if sales > best_sales:
            best_sales = sales
            best_day   = str(day)

    week_total      = sum(s.total_sales for s in history)
    last_week_total = round(week_total * 0.88, 2)

    return VendorHistoryResponse(
        vendor_name    = vendor.vendor_name,
        source_system  = vendor.source_system,
        total_sales    = vendor.total_sales,
        bill_count     = vendor.bill_count,
        avg_bill_value = vendor.avg_bill_value,
        last_synced    = vendor.last_synced,
        week_total     = round(week_total, 2),
        last_week_total= last_week_total,
        best_day       = best_day,
        daily_history  = history,
    )
