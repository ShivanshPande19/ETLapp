from pydantic import BaseModel
from typing import List

class Court(BaseModel):
    id: int
    name: str
    location: str
    status: str

class CourtsResponse(BaseModel):
    courts: List[Court]