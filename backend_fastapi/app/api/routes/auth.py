# backend_fastapi/app/api/routes/auth.py
import logging
import os

from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from jose import JWTError, ExpiredSignatureError
from sqlalchemy.orm import Session
from ...schemas.auth import LoginRequest, TokenResponse
from ...schemas.onboarding import SetPasswordRequest
from ...services.auth_service import login_manager
from ...database import get_db
from ...models.manager import Manager
from ...models.staff import Staff
from ...core.security import hash_password, decode_token
from pydantic import BaseModel

logger = logging.getLogger("auth")

router = APIRouter()

_templates_dir = os.path.join(os.getcwd(), "app", "templates")
templates = Jinja2Templates(directory=_templates_dir)

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


# ─── Set-password (onboarding magic link) ────────────────────────────────────

@router.get("/set-password", response_class=HTMLResponse, include_in_schema=False)
def set_password_page(request: Request, token: str = ""):
    """Browser page where a newly-onboarded outlet owner sets their password."""
    return templates.TemplateResponse(
        request=request,
        name="set_password.html",
        context={"request": request, "token": token},
    )


@router.post("/set-password")
def set_password(req: SetPasswordRequest, db: Session = Depends(get_db)):
    if not req.new_password or len(req.new_password) < 6:
        raise HTTPException(
            status_code=400, detail="Password must be at least 6 characters."
        )
    try:
        payload = decode_token(req.token)
    except ExpiredSignatureError:
        raise HTTPException(
            status_code=400,
            detail="This link has expired. Ask the ETL manager to resend it.",
        )
    except JWTError:
        raise HTTPException(status_code=400, detail="Invalid or broken link.")

    if payload.get("purpose") != "set_password":
        raise HTTPException(status_code=400, detail="Invalid link.")

    email = payload.get("sub")
    mid = payload.get("mid")
    manager = db.query(Manager).filter(
        Manager.id == mid, Manager.email == email
    ).first()
    if not manager:
        raise HTTPException(status_code=404, detail="Account not found.")

    manager.hashed_password = hash_password(req.new_password)
    manager.is_active = True
    db.commit()
    return {"message": "Password set successfully. You can now log in."}