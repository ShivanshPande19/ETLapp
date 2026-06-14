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