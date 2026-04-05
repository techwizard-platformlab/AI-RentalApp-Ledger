from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    environment: str = "dev"
    log_level: str = "INFO"
    rental_service_url: str = "http://rental-service:8001"
    ledger_service_url: str = "http://ledger-service:8002"

    model_config = {"env_file": ".env", "case_sensitive": False}


settings = Settings()
