# backend_fastapi/app/api/routes/auth.py
import logging

from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.orm import Session
from ...schemas.auth import LoginRequest, TokenResponse
from ...services.auth_service import login_manager
from ...database import get_db
from ...models.manager import Manager
from ...models.staff import Staff
from ...core.security import hash_password
from pydantic import BaseModel

logger = logging.getLogger("auth")

router = APIRouter()

@router.post("/login", response_model=TokenResponse)
def login(request: LoginRequest, db: Session = Depends(get_db)):
    try:
        result = login_manager(request, db)
        if not result:
            raise HTTPException(status_code=401, detail="Invalid email or password")
        return result
    except HTTPException:
        raise
    except Exception as e:
        # ✅ Log the real error server-side; never leak internals to the client.
        logger.exception("Login failed unexpectedly: %s", e)
        raise HTTPException(
            status_code=500,
            detail="Something went wrong. Please try again.",
        )

class SeedRequest(BaseModel):
    name: str
    email: str
    password: str
    role: str = "manager"

@router.post("/seed", include_in_schema=False)
def seed_user(req: SeedRequest, db: Session = Depends(get_db)):
    exists = db.query(Manager).filter(Manager.email == req.email).first()
    if exists:
        raise HTTPException(status_code=400, detail="Already exists")
    user = Manager(
        name=req.name,
        email=req.email,
        hashed_password=hash_password(req.password),
        role=req.role,
    )
    db.add(user)
    db.commit()
    return {"message": f"{req.role} created: {req.email}"}