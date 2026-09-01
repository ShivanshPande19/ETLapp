import os

from pydantic_settings import BaseSettings

# Built-in placeholder secret. Fine for local dev; refused on Railway (see the
# production guard at the bottom of this file).
INSECURE_DEFAULT_SECRET = "changethisinsecretkey123"


class Settings(BaseSettings):
    APP_NAME: str = "ETL Manager API"
    APP_VERSION: str = "1.0.0"
    # Fail-safe default: OFF. FastAPI's debug mode leaks stack traces, so it must
    # never be on by accident in production. Local dev opts in with DEBUG=true.
    DEBUG: bool = False
    SECRET_KEY: str = INSECURE_DEFAULT_SECRET

    # CORS allowed origins, comma-separated
    # (e.g. "https://app.example.com,https://admin.example.com"). Empty string
    # => wildcard "*", which is fine for the native mobile app (it sends no
    # Origin header); set explicit origins once a browser client is added.
    ALLOWED_ORIGINS: str = ""
    # 30 days — app stays signed in for a month; expiry is now handled
    # gracefully (a 401 signs the user out cleanly and routes to login).
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30

    # Database
    DATABASE_URL: str = "sqlite:///./app/etl.db"

    # File uploads (selfies, onboarding docs). On Railway point this at a
    # mounted volume path (e.g. /app/data/uploads) so files survive redeploys.
    UPLOAD_DIR: str = "uploads"

    # Public base URL of THIS backend (e.g. https://xxx.up.railway.app).
    # Used to build absolute links (set-password magic link, doc URLs).
    PUBLIC_BASE_URL: str = ""

    # Resend transactional email (https://resend.com). If RESEND_API_KEY is
    # empty, email sending is skipped gracefully (links are logged / returned).
    RESEND_API_KEY: str = ""
    EMAIL_FROM: str = "ETL Onboarding <onboarding@resend.dev>"

    # Petpooja API credentials
    PETPOOJA_APP_KEY: str = ""
    PETPOOJA_APP_SECRET: str = ""
    PETPOOJA_ACCESS_TOKEN: str = ""
    PETPOOJA_COOKIE: str = ""

    # ── Firebase Cloud Messaging (push notifications) ─────────────────────────
    # FIREBASE_PROJECT_ID:       the Firebase project id, e.g. "etl-manager".
    # FIREBASE_CREDENTIALS_JSON: the FULL service-account JSON as a single
    #                            env var (Railway has no secret-file mount, so
    #                            paste the file contents). Never commit this.
    #
    # If either is empty, push sending is skipped gracefully — in-app notices
    # and SSE keep working, so local dev needs no Firebase setup at all.
    FIREBASE_PROJECT_ID: str = ""
    FIREBASE_CREDENTIALS_JSON: str = ""

    @property
    def allowed_origins_list(self) -> list[str]:
        """Parsed ALLOWED_ORIGINS. Empty config => ["*"]."""
        items = [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]
        return items or ["*"]

    class Config:
        env_file = ".env"
        # Ye line zaroori hai taaki `.env` file mein agar koi extra 
        # variable ho toh Pydantic use ignore kar de aur crash na ho
        extra = "ignore" 

settings = Settings()


# ─── Production safety guards ─────────────────────────────────────────────────
# Railway sets RAILWAY_ENVIRONMENT_NAME on every deploy, so we use it to detect
# "running in production" without needing an extra flag. Local dev never sets
# it, so none of these guards fire on your machine.
_ON_RAILWAY = bool(os.getenv("RAILWAY_ENVIRONMENT_NAME"))

if _ON_RAILWAY and settings.SECRET_KEY == INSECURE_DEFAULT_SECRET:
    # Refuse to boot with the placeholder key in production: JWTs signed with a
    # publicly-known secret can be forged, letting anyone impersonate any user.
    raise RuntimeError(
        "SECRET_KEY is still the built-in insecure default on Railway. "
        "Set a strong, random SECRET_KEY environment variable before serving "
        "traffic."
    )

# Persist uploads on the mounted Railway volume by default (same /app/data root
# database.py uses for the SQLite fallback), so attendance selfies and
# onboarding documents survive redeploys instead of vanishing with the
# container's ephemeral filesystem. An explicit UPLOAD_DIR env var still wins.
#   ⚠️ This only actually persists if a Railway Volume is mounted at /app/data.
if _ON_RAILWAY and not os.getenv("UPLOAD_DIR"):
    settings.UPLOAD_DIR = "/app/data/uploads"