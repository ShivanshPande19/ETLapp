# backend_fastapi/app/services/auth_service.py

from sqlalchemy.orm import Session
from ..models.manager import Manager
from ..models.staff import Staff
from ..core.security import verify_password, create_access_token
from ..schemas.auth import LoginRequest, TokenResponse

def login_manager(request: LoginRequest, db: Session) -> TokenResponse | None:
    print(f"[LOGIN] Trying email: '{request.email}'")

    # 1. Pehle managers mein dhundo
    user = db.query(Manager).filter(
        Manager.email == request.email,
        Manager.is_active == True
    ).first()

    # 2. Nahi mila toh staff mein dhundo
    if not user:
        user = db.query(Staff).filter(
            Staff.email == request.email,
            Staff.is_active == True
        ).first()

    print(f"[LOGIN] User found: {user}")

    if not user:
        return None

    # 3. Password verify karo
    result = verify_password(request.password, user.hashed_password)
    print(f"[LOGIN] Password match: {result}")

    if not result:
        return None

    # 4. Token banao
    token = create_access_token({
        "sub": user.email,
        "name": user.name,
        "role": user.role,
    })

    # 5. TokenResponse build karo (Yahan fix hai)
    try:
        # getattr ka use isliye kar rahe hain taaki agar object mein 
        # field na ho toh code crash na ho, balki None mil jaye
        response = TokenResponse(
            access_token=token,
            token_type="bearer",
            manager_name=user.name,
            manager_email=user.email,
            role=user.role,
            zone=getattr(user, "court_id", None), 
            outlet_id=getattr(user, "outlet_id", None)  # ✅ FIX YAHAN HAI
        )
        print(f"[LOGIN] TokenResponse built: {response}")
        return response
    except Exception as e:
        print(f"[LOGIN] TokenResponse FAILED: {e}")
        return None