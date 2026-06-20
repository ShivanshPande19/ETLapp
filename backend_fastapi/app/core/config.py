from pydantic_settings import BaseSettings
from typing import Optional

class Settings(BaseSettings):
    APP_NAME: str = "ETL Manager API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    SECRET_KEY: str = "changethisinsecretkey123"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24

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

    # Spotify credentials
    spotify_client_id: Optional[str] = None
    spotify_client_secret: Optional[str] = None
    spotify_redirect_uri: Optional[str] = None

    class Config:
        env_file = ".env"
        # Ye line zaroori hai taaki `.env` file mein agar koi extra 
        # variable ho toh Pydantic use ignore kar de aur crash na ho
        extra = "ignore" 

settings = Settings()