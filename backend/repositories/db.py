"""
backend/repositories/db.py
SQLite database initialisation and connection management.
"""
from __future__ import annotations

import sqlite3
import os
from contextlib import contextmanager
from typing import Generator


_DATABASE_PATH: str = "backend/data/boardmate.db"


def set_database_path(path: str) -> None:
    global _DATABASE_PATH
    _DATABASE_PATH = path


def get_database_path() -> str:
    return _DATABASE_PATH


class _PostgresCursorWrapper:
    """Wraps psycopg2 cursor to provide SQLite-compatible execution."""
    def __init__(self, cur):
        self._cur = cur

    def execute(self, sql: str, params=None):
        pg_sql = sql.replace("?", "%s")
        self._cur.execute(pg_sql, params)
        return self

    def fetchone(self):
        return self._cur.fetchone()

    def fetchall(self):
        return self._cur.fetchall()

    def fetchmany(self, size=None):
        return self._cur.fetchmany(size)

    @property
    def rowcount(self):
        return self._cur.rowcount

    def close(self):
        self._cur.close()


class _PostgresConnectionWrapper:
    """Wraps psycopg2 connection to provide SQLite-like connection.execute(...)."""
    def __init__(self, conn):
        self._conn = conn

    def cursor(self):
        import psycopg2.extras
        return _PostgresCursorWrapper(
            self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        )

    def execute(self, sql: str, params=None):
        import psycopg2.extras
        cur = self._conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        pg_sql = sql.replace("?", "%s")
        cur.execute(pg_sql, params)
        return _PostgresCursorWrapper(cur)

    def commit(self):
        self._conn.commit()

    def rollback(self):
        self._conn.rollback()

    def close(self):
        self._conn.close()


def _connect_postgres(db_url: str):
    import psycopg2
    try:
        return psycopg2.connect(db_url)
    except psycopg2.OperationalError as e:
        err_msg = str(e)
        if "could not translate host name" in err_msg and "supabase.co" in db_url:
            import re
            m = re.match(r"^postgresql://([^:]+):([^@]+)@db\.([^.]+)\.supabase\.co(?::\d+)?/(.+)$", db_url)
            if m:
                user, pw, proj, dbname = m.groups()
                for region in ["ap-south-1", "ap-southeast-1", "us-east-1", "eu-central-1"]:
                    pooler_host = f"aws-0-{region}.pooler.supabase.com"
                    pooler_url = f"postgresql://postgres.{proj}:{pw}@{pooler_host}:6543/{dbname}"
                    try:
                        return psycopg2.connect(pooler_url, connect_timeout=5)
                    except Exception:
                        continue
        raise


@contextmanager
def get_db():
    """Context manager returning a thread-local SQLite or PostgreSQL connection."""
    try:
        from ..config import get_config
        cfg = get_config()
    except Exception:
        cfg = None
    raw_target = cfg.database_path if (cfg and cfg.is_postgres) else _DATABASE_PATH
    db_target = str(raw_target)

    if db_target.startswith("postgresql://"):
        import psycopg2.extras
        conn = _connect_postgres(db_target)
        wrapped = _PostgresConnectionWrapper(conn)
        try:
            yield wrapped
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()
    else:
        os.makedirs(os.path.dirname(os.path.abspath(db_target)), exist_ok=True)
        conn = sqlite3.connect(db_target)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        try:
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS sources (
    source_id        TEXT PRIMARY KEY,
    title            TEXT NOT NULL,
    subject_id       TEXT NOT NULL,
    medium           TEXT NOT NULL DEFAULT 'English',
    board            TEXT NOT NULL,
    curriculum       TEXT NOT NULL,
    class_level      INTEGER NOT NULL DEFAULT 10,
    edition          TEXT NOT NULL,
    publisher        TEXT NOT NULL DEFAULT '',
    source_uri       TEXT,
    rights_status    TEXT NOT NULL,
    rights_notes     TEXT NOT NULL DEFAULT '',
    file_sha256      TEXT,
    ingestion_status TEXT NOT NULL DEFAULT 'pending',
    created_at       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chapters (
    chapter_id      TEXT PRIMARY KEY,
    source_id       TEXT NOT NULL REFERENCES sources(source_id),
    subject_id      TEXT NOT NULL,
    chapter_number  INTEGER NOT NULL,
    title           TEXT NOT NULL,
    start_pdf_page  INTEGER NOT NULL DEFAULT 0,
    end_pdf_page    INTEGER NOT NULL DEFAULT 0,
    status          TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS passages (
    passage_id          TEXT PRIMARY KEY,
    source_id           TEXT NOT NULL REFERENCES sources(source_id),
    subject_id          TEXT NOT NULL,
    chapter_id          TEXT NOT NULL,
    chapter_title       TEXT NOT NULL,
    language            TEXT NOT NULL DEFAULT 'en',
    pdf_page_index      INTEGER NOT NULL,
    printed_page_label  TEXT NOT NULL DEFAULT '',
    section_heading     TEXT,
    text                TEXT NOT NULL,
    extraction_method   TEXT NOT NULL DEFAULT 'pymupdf',
    extraction_quality  TEXT NOT NULL DEFAULT 'unreviewed',
    content_hash        TEXT NOT NULL DEFAULT '',
    embedding_model     TEXT,
    index_version       TEXT
);

CREATE TABLE IF NOT EXISTS questions (
    question_id         TEXT PRIMARY KEY,
    subject_id          TEXT NOT NULL,
    source_id           TEXT NOT NULL,
    chapter_id          TEXT NOT NULL,
    chapter_title       TEXT NOT NULL,
    language            TEXT NOT NULL DEFAULT 'en',
    origin              TEXT NOT NULL,
    question_type       TEXT NOT NULL DEFAULT 'mcq',
    question_text       TEXT NOT NULL,
    options_json        TEXT NOT NULL,
    correct_option_id   TEXT NOT NULL,
    explanation         TEXT NOT NULL DEFAULT '',
    source_refs_json    TEXT NOT NULL DEFAULT '[]',
    difficulty          TEXT NOT NULL DEFAULT 'unknown',
    review_status       TEXT NOT NULL DEFAULT 'draft',
    review_notes        TEXT,
    reviewed_by         TEXT,
    reviewed_at         TEXT,
    model_provider      TEXT,
    model_id            TEXT,
    prompt_version      TEXT,
    content_version     INTEGER NOT NULL DEFAULT 1,
    created_at          TEXT NOT NULL,
    updated_at          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS student_attempts (
    attempt_id              TEXT PRIMARY KEY,
    local_student_id        TEXT NOT NULL,
    question_id             TEXT NOT NULL REFERENCES questions(question_id),
    selected_option_id      TEXT,
    is_correct              INTEGER NOT NULL DEFAULT 0,
    mode                    TEXT NOT NULL DEFAULT 'practice',
    attempted_at            TEXT NOT NULL,
    question_content_version INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS generation_jobs (
    job_id                  TEXT PRIMARY KEY,
    subject_id              TEXT NOT NULL,
    source_id               TEXT NOT NULL,
    chapter_id              TEXT NOT NULL,
    requested_count         INTEGER NOT NULL,
    status                  TEXT NOT NULL DEFAULT 'pending',
    retrieved_passage_ids   TEXT NOT NULL DEFAULT '[]',
    model_provider          TEXT NOT NULL DEFAULT 'groq',
    model_id                TEXT NOT NULL DEFAULT '',
    prompt_version          TEXT NOT NULL DEFAULT '',
    candidate_question_ids  TEXT NOT NULL DEFAULT '[]',
    validation_summary      TEXT NOT NULL DEFAULT '{}',
    created_at              TEXT NOT NULL,
    completed_at            TEXT
);

CREATE INDEX IF NOT EXISTS idx_questions_subject_chapter
    ON questions(subject_id, chapter_id, review_status);
CREATE INDEX IF NOT EXISTS idx_passages_subject_chapter
    ON passages(subject_id, chapter_id);
CREATE INDEX IF NOT EXISTS idx_attempts_student
    ON student_attempts(local_student_id, question_id);
"""


def init_db(path: str | None = None) -> None:
    """Create tables if they don't exist."""
    if path:
        set_database_path(path)
    try:
        from ..config import get_config
        cfg = get_config()
    except Exception:
        cfg = None
    raw_target = cfg.database_path if (cfg and cfg.is_postgres) else _DATABASE_PATH
    db_target = str(raw_target)
    if not db_target.startswith("postgresql://"):
        with get_db() as conn:
            conn.executescript(SCHEMA_SQL)
