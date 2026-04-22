from fastapi import APIRouter
from ...schemas.court import CourtsResponse
from ...services.court_service import get_all_courts

router = APIRouter()

@router.get("/", response_model=CourtsResponse)
def list_courts():
    return get_all_courts()