# backend_fastapi/app/services/auth_service.py

import logging

from sqlalchemy.orm import Session
from ..models.manager import Manager
from ..models.staff import Staff
from ..core.security import verify_password, create_access_token
from ..schemas.auth import LoginRequest, TokenResponse

logger = logging.getLogger("auth")


def login_manager(request: LoginRequest, db: Session) -> TokenResponse | None:
    # 1. Look in managers first
    user = db.query(Manager).filter(
        Manager.email == request.email,
        Manager.is_active == True,
    ).first()

    # 2. Fall back to staff
    if not user:
        user = db.query(Staff).filter(
            Staff.email == request.email,
            Staff.is_active == True,
        ).first()

    if not user:
        return None

    # 3. Verify password
    #
    # NOTE: never log the email, the looked-up user, or the password-match
    # result — that writes account identifiers / auth internals into the server
    # logs on every single login. The caller turns a None return into a generic
    # 401, so nothing sensitive needs to be logged here.
    if not verify_password(request.password, user.hashed_password):
        return None

    # 4. Mint the access token
    token = create_access_token({
        "sub": user.email,
        "name": user.name,
        "role": user.role,
    })

    # 5. Build the response
    try:
        return TokenResponse(
            access_token=token,
            token_type="bearer",
            manager_name=user.name,
            manager_email=user.email,
            role=user.role,
            # getattr keeps this resilient if a user type lacks these columns.
            zone=getattr(user, "court_id", None),
            outlet_id=getattr(user, "outlet_id", None),
        )
    except Exception as e:  # noqa: BLE001 — log server-side, surface generic 500
        logger.exception("Failed to build login response: %s", e)
        return None
