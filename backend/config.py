"""
backend/config.py
Centralised configuration loaded from environment variables.
Never import secrets from here into Flutter or logs.
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from urllib.parse import quote_plus


def sanitize_database_url(url: str) -> str:
    """Normalize and sanitize PostgreSQL / Supabase connection strings."""
    if not url:
        return ""
    from urllib.parse import quote_plus, unquote
    url = url.strip().strip("'").strip('"')
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://"):]

    match = re.match(r"^(postgresql://)([^:]+):(.*)@([^@/]+)(/[^?]+)?(\?.*)?$", url)
    if match:
        prefix, user, raw_pass, host_port, dbname, query = match.groups()
        if raw_pass.startswith("[") and raw_pass.endswith("]"):
            raw_pass = raw_pass[1:-1]
        clean_pass = quote_plus(unquote(raw_pass))
        dbname = dbname or "/postgres"
        if dbname == "/postgress":
            dbname = "/postgres"
        query = query or ""
        return f"{prefix}{user}:{clean_pass}@{host_port}{dbname}{query}"
    return url


@dataclass(frozen=True)
class Config:
    groq_api_key: str
    groq_model: str
    groq_max_retries: int
    groq_timeout_seconds: float
    flask_secret_key: str
    admin_api_key: str
    database_path: str
    embedding_model: str
    faiss_index_path: str
    max_retrieval_chunks: int
    debug: bool

    @classmethod
    def from_env(cls) -> "Config":
        import logging
        logger = logging.getLogger(__name__)

        try:
            from dotenv import load_dotenv
            load_dotenv()
        except ImportError:
            pass

        groq_api_key = os.environ.get("GROQ_API_KEY", "").strip()
        if not groq_api_key or groq_api_key.startswith("your_"):
            logger.warning(
                "GROQ_API_KEY is not set or contains a placeholder. "
                "AI generation and live Q&A will be unavailable, but verified practice is fully functional."
            )
        admin_api_key = os.environ.get("ADMIN_API_KEY", "change_this_admin_key").strip()
        flask_secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-secret-key-boardmate10").strip()

        # Support standard DATABASE_URL provided by cloud hosts like Supabase and Render
        db_url = os.environ.get("DATABASE_URL", "").strip()
        if db_url:
            db_url = sanitize_database_url(db_url)

        database_path = db_url or os.environ.get("DATABASE_PATH", "backend/data/boardmate.db")

        return cls(
            groq_api_key=groq_api_key,
            groq_model=os.environ.get("GROQ_MODEL", "openai/gpt-oss-120b"),
            groq_max_retries=int(os.environ.get("GROQ_MAX_RETRIES", "3")),
            groq_timeout_seconds=float(os.environ.get("GROQ_TIMEOUT_SECONDS", "30")),
            flask_secret_key=flask_secret_key,
            admin_api_key=admin_api_key,
            database_path=database_path,
            embedding_model=os.environ.get("EMBEDDING_MODEL", "all-MiniLM-L6-v2"),
            faiss_index_path=os.environ.get("FAISS_INDEX_PATH", "backend/rag/indexes/"),
            max_retrieval_chunks=int(os.environ.get("MAX_RETRIEVAL_CHUNKS", "6")),
            debug=os.environ.get("FLASK_DEBUG", "0") == "1",
        )

    @property
    def is_postgres(self) -> bool:
        """Returns True if connected to PostgreSQL / Supabase."""
        return self.database_path.startswith("postgresql://")


_config: Config | None = None


def get_config() -> Config:
    """Return the singleton Config instance, loading from env on first call."""
    global _config
    if _config is None:
        _config = Config.from_env()
    return _config


def reset_config() -> None:
    """Reset singleton (used in tests)."""
    global _config
    _config = None
