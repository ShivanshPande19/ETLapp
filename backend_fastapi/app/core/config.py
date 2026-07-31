from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    APP_NAME: str = "ETL Manager API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    SECRET_KEY: str = "changethisinsecretkey123"
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

    class Config:
        env_file = ".env"
        # Ye line zaroori hai taaki `.env` file mein agar koi extra 
        # variable ho toh Pydantic use ignore kar de aur crash na ho
        extra = "ignore" 

settings = Settings()