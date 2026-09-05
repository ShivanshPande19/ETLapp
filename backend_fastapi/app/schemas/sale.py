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


class SalesTrendPoint(BaseModel):
    label: str          # short axis label (e.g. "Mon", "12", "Jun")
    date: str           # ISO date the bucket starts on
    total_sales: float
    total_bills: int


class SalesTrendResponse(BaseModel):
    period: str
    bucket: str         # "daily" | "monthly"
    points: List[SalesTrendPoint]


class ComparePoint(BaseModel):
    """One aligned bucket in a this-vs-last comparison (e.g. Mon-vs-Mon,
    week1-vs-week1, Jan-vs-Jan)."""
    label: str
    current_sales: float
    current_bills: int
    previous_sales: float
    previous_bills: int


class SalesCompareResponse(BaseModel):
    """Fair, SAME-SPAN comparison of the current period-so-far against the same
    number of days in the previous period. The totals/growth compare like for
    like (partial vs partial); the ``points`` series is aligned bucket-by-bucket
    for a side-by-side chart (previous period shown in full for context)."""
    granularity: str        # "week" | "month" | "year"
    bucket: str             # "daily" | "weekly" | "monthly"
    current_label: str      # e.g. "This week (01–05 Sep)"
    previous_label: str     # e.g. "Last week (25–29 Aug)"
    current_total: float    # sum over the same span (partial)
    previous_total: float   # sum over the same span in the previous period
    current_bills: int
    previous_bills: int
    growth_pct: float       # (current_total - previous_total)/previous_total*100
    points: List[ComparePoint]