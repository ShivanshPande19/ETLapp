from pydantic import BaseModel
from typing import List

class VendorSaleDetail(BaseModel):
    vendor_name: str
    source_system: str
    total_sales: float
    bill_count: int
    avg_bill_value: float
    last_synced: str

class SalesSummaryResponse(BaseModel):
    date: str
    period: str
    total_sales: float
    total_bills: int
    avg_bill_value: float
    vendors: List[VendorSaleDetail]

class DailySnapshot(BaseModel):
    date: str
    total_sales: float
    total_bills: int

class VendorHistoryResponse(BaseModel):
    vendor_name: str
    source_system: str
    total_sales: float
    bill_count: int
    avg_bill_value: float
    last_synced: str
    week_total: float
    last_week_total: float
    best_day: str
    daily_history: List[DailySnapshot]
