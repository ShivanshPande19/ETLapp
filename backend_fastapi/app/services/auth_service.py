# backend_fastapi/app/services/auth_service.py
from sqlalchemy.orm import Session
from ..models.manager import Manager
from ..models.staff import Staff
from ..core.security import verify_password, create_access_token
from ..schemas.auth import LoginRequest, TokenResponse

def login_manager(request: LoginRequest, db: Session) -> TokenResponse | None:
    # Pehle managers mein dhundo
    user = db.query(Manager).filter(
        Manager.email == request.email,
        Manager.is_active == True
    ).first()

    # Nahi mila toh staff mein dhundo
    if not user:
        user = db.query(Staff).filter(
            Staff.email == request.email,
            Staff.is_active == True
        ).first()

    if not user:
        return None

    if not verify_password(request.password, user.hashed_password):
        return None

    token = create_access_token({
        "sub": user.email,
        "name": user.name,
        "role": user.role,
    })

    return TokenResponse(
        access_token=token,
        manager_name=user.name,
        manager_email=user.email,
        role=user.role,
        zone=getattr(user, "court_id", None),
    )

def login_manager(request: LoginRequest, db: Session) -> TokenResponse | None:
    print(f"[LOGIN] Trying email: '{request.email}'")  # ✅ add karo

    user = db.query(Manager).filter(
        Manager.email == request.email,
        Manager.is_active == True
    ).first()

    if not user:
        user = db.query(Staff).filter(
            Staff.email == request.email,
            Staff.is_active == True
        ).first()

    print(f"[LOGIN] User found: {user}")  # ✅ add karo

    if not user:
        return None

    result = verify_password(request.password, user.hashed_password)
    print(f"[LOGIN] Password match: {result}")  # ✅ add karo

    if not result:
        return None
    ...

def login_manager(request: LoginRequest, db: Session) -> TokenResponse | None:
    print(f"[LOGIN] Trying email: '{request.email}'")

    user = db.query(Manager).filter(
        Manager.email == request.email,
        Manager.is_active == True
    ).first()

    if not user:
        user = db.query(Staff).filter(
            Staff.email == request.email,
            Staff.is_active == True
        ).first()

    print(f"[LOGIN] User found: {user}")

    if not user:
        return None

    result = verify_password(request.password, user.hashed_password)
    print(f"[LOGIN] Password match: {result}")

    if not result:
        return None

    token = create_access_token({
        "sub": user.email,
        "name": user.name,
        "role": user.role,
    })

    # ✅ Try/except lagao yahan
    try:
        response = TokenResponse(
            access_token=token,
            manager_name=user.name,
            manager_email=user.email,
            role=user.role,
            zone=user.court_id if hasattr(user, 'court_id') else None,
        )
        print(f"[LOGIN] TokenResponse built: {response}")
        return response
    except Exception as e:
        print(f"[LOGIN] TokenResponse FAILED: {e}")
        return None