from ..core.database import managers_db, staff_db
from ..core.security import verify_password, create_access_token
from ..schemas.auth import LoginRequest, TokenResponse

def login_manager(request: LoginRequest) -> TokenResponse | None:
    user = managers_db.get(request.email) or staff_db.get(request.email)
    if not user:
        return None
    if not verify_password(request.password, user["password"]):
        return None
    token = create_access_token({"sub": user["email"], "name": user["name"], "role": user["role"]})
    return TokenResponse(
        access_token=token,
        manager_name=user["name"],
        manager_email=user["email"],
        role=user["role"],
        zone=user.get("zone"),
    )
