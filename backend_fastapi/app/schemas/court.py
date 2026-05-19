from pydantic import BaseModel
from typing import List, Optional

class Court(BaseModel):
    id: int
    court_uid: Optional[str] = None
    name: str
    location: Optional[str] = "Food Court"
    is_active: bool

    class Config:
        from_attributes = True

class CourtsResponse(BaseModel):
    courts: List[Court]