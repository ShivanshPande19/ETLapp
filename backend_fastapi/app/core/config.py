from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    APP_NAME: str = "ETL Manager API"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = True
    SECRET_KEY: str = "changethisinsecretkey123"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24

    class Config:
        env_file = ".env"

settings = Settings()