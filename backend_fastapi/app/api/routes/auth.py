# backend_fastapi/app/api/routes/auth.py
import logging
import os

from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from jose import JWTError, ExpiredSignatureError
from sqlalchemy import func
from sqlalchemy.orm import Session
from ...schemas.auth import LoginRequest, TokenResponse
from ...schemas.onboarding import SetPasswordRequest
from ...services.auth_service import login_manager
from ...services.email_service import send_email
from ...database import get_db
from ...models.manager import Manager
from ...models.staff import Staff
from ...core.config import settings
from ...core.security import hash_password, decode_token, create_token
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



# ─── Forgot / reset password (works for managers AND staff) ──────────────────

# Reset link valid for 30 minutes.
_RESET_PW_EXPIRY_MIN = 30


class ForgotPasswordRequest(BaseModel):
    email: str


def _reset_password_email_html(name: str, link: str) -> str:
    return f"""
    <div style="font-family: Arial, sans-serif; max-width: 520px; margin: 0 auto;">
      <h2 style="color:#0A0A0A;">Reset your <span style="color:#D02128;">ETL</span> password</h2>
      <p style="color:#333; font-size:15px;">Hi {name},</p>
      <p style="color:#333; font-size:15px;">
        We received a request to reset your password. Tap the button below to
        choose a new one. This link expires in 30 minutes.
      </p>
      <p style="text-align:center; margin:28px 0;">
        <a href="{link}" style="background:#D02128; color:#fff; text-decoration:none;
           padding:14px 28px; border-radius:12px; font-weight:bold; font-size:15px;">
          Reset Password
        </a>
      </p>
      <p style="color:#888; font-size:13px;">
        If you didn't request this, you can safely ignore this email — your
        password won't change.
      </p>
    </div>
    """


@router.post("/forgot-password")
async def forgot_password(req: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Email a password-reset link. Always returns the same generic response so
    callers can't probe which emails are registered."""
    email = (req.email or "").strip().lower()
    generic = {
        "message": "If an account exists for that email, a reset link has been sent."
    }
    if not email:
        return generic

    user_type = uid = name = None
    manager = db.query(Manager).filter(
        func.lower(Manager.email) == email, Manager.is_active == True
    ).first()
    if manager:
        user_type, uid, name = "manager", manager.id, manager.name
    else:
        staff = db.query(Staff).filter(
            func.lower(Staff.email) == email, Staff.is_active == True
        ).first()
        if staff:
            user_type, uid, name = "staff", staff.id, staff.name

    if user_type is None:
        return generic  # don't reveal non-existence

    token = create_token(
        {"sub": email, "purpose": "reset_password", "uid": uid, "utype": user_type},
        _RESET_PW_EXPIRY_MIN,
    )
    base = (settings.PUBLIC_BASE_URL or "").rstrip("/")
    link = f"{base}/auth/reset-password?token={token}"
    await send_email(
        to=email,
        subject="Reset your ETL password",
        html=_reset_password_email_html(name or "there", link),
    )
    return generic


@router.get("/reset-password", response_class=HTMLResponse, include_in_schema=False)
def reset_password_page(request: Request, token: str = ""):
    """Browser page where a user sets a new password from the reset link."""
    return templates.TemplateResponse(
        request=request,
        name="reset_password.html",
        context={"request": request, "token": token},
    )


@router.post("/reset-password")
def reset_password(req: SetPasswordRequest, db: Session = Depends(get_db)):
    if not req.new_password or len(req.new_password) < 6:
        raise HTTPException(
            status_code=400, detail="Password must be at least 6 characters."
        )
    try:
        payload = decode_token(req.token)
    except ExpiredSignatureError:
        raise HTTPException(
            status_code=400,
            detail="This reset link has expired. Please request a new one.",
        )
    except JWTError:
        raise HTTPException(status_code=400, detail="Invalid or broken link.")

    if payload.get("purpose") != "reset_password":
        raise HTTPException(status_code=400, detail="Invalid link.")

    email = (payload.get("sub") or "").lower()
    uid = payload.get("uid")
    utype = payload.get("utype")

    if utype == "manager":
        user = db.query(Manager).filter(
            Manager.id == uid, func.lower(Manager.email) == email
        ).first()
    elif utype == "staff":
        user = db.query(Staff).filter(
            Staff.id == uid, func.lower(Staff.email) == email
        ).first()
    else:
        user = None

    if not user:
        raise HTTPException(status_code=404, detail="Account not found.")

    user.hashed_password = hash_password(req.new_password)
    db.commit()
    return {"message": "Password reset successfully. You can now log in."}
