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
    total_sales: float
    total_bills: int
    avg_bill_value: float
    vendors: List[VendorSaleDetail]