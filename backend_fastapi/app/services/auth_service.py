from ..core.database import managers_db
from ..core.security import verify_password, create_access_token
from ..schemas.auth import LoginRequest, TokenResponse

def login_manager(request: LoginRequest) -> TokenResponse | None:
    manager = managers_db.get(request.email)
    if not manager:
        return None
    if not verify_password(request.password, manager["password"]):
        return None
    token = create_access_token({"sub": manager["email"], "name": manager["name"]})
    return TokenResponse(
        access_token=token,
        manager_name=manager["name"],
        manager_email=manager["email"],
    )