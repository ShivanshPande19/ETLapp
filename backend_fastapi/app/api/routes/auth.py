from fastapi import APIRouter, HTTPException
from ...schemas.auth import LoginRequest, TokenResponse
from ...services.auth_service import login_manager

router = APIRouter()

@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest):
    result = login_manager(request)
    if not result:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    return result