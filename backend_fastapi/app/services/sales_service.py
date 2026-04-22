from ..schemas.sale import SalesSummaryResponse, VendorSaleDetail
from datetime import date
from typing import Optional

# Mock data per court — will come from real POS connectors later
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

def get_sales_summary(court_id: Optional[int] = None) -> SalesSummaryResponse:
    if court_id and court_id in COURT_SALES:
        vendors = COURT_SALES[court_id]["vendors"]
    else:
        # Combine all courts
        vendors = []
        for court_data in COURT_SALES.values():
            vendors.extend(court_data["vendors"])

    total_sales = sum(v.total_sales for v in vendors)
    total_bills = sum(v.bill_count for v in vendors)
    return SalesSummaryResponse(
        date=str(date.today()),
        total_sales=total_sales,
        total_bills=total_bills,
        avg_bill_value=round(total_sales / total_bills, 2) if total_bills else 0,
        vendors=vendors,
    )