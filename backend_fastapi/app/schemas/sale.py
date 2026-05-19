from pydantic import BaseModel
from typing import List, Optional


class CourtCreate(BaseModel):
    name: str
    manager_id: Optional[int] = None


class CourtResponse(BaseModel):
    id: int
    court_uid: str
    name: str
    manager_id: Optional[int]
    is_active: int

    class Config:
        from_attributes = True


class OutletCreate(BaseModel):
    vendor_name: str
    rest_id: str


class OutletResponse(BaseModel):
    id: int
    court_id: int
    vendor_name: str
    rest_id: str
    is_active: int

    class Config:
        from_attributes = True


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