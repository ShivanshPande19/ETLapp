from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ...schemas.court import CourtsResponse
from ...services.court_service import get_all_courts
from ...database import get_db

router = APIRouter()

@router.get("/", response_model=CourtsResponse)
def list_courts(db: Session = Depends(get_db)):
    return get_all_courts(db)