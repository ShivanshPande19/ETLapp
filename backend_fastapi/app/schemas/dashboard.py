from pydantic import BaseModel
from typing import List

class VendorSale(BaseModel):
    vendor_name: str
    source_system: str
    total_sales: float
    bill_count: int

class DashboardSummary(BaseModel):
    date: str
    total_sales: float
    total_bills: int
    vendor_breakdown: List[VendorSale]
    last_synced: str