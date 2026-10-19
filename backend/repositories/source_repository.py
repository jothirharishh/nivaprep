"""
backend/repositories/source_repository.py
CRUD for textbook sources and chapters.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional

from ..models.source import IngestionStatus, RightsStatus, Source
from .db import get_db


SUBJECT_IDS = {"tamil", "english", "mathematics", "science", "social_science"}

SUBJECT_DISPLAY = {
    "tamil": "Tamil",
    "english": "English",
    "mathematics": "Mathematics",
    "science": "Science",
    "social_science": "Social Science",
}


class SourceRepository:

    def get_by_id(self, source_id: str) -> Optional[Source]:
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM sources WHERE source_id = ?", (source_id,)
            ).fetchone()
        return self._row_to_source(dict(row)) if row else None

    def list_all(self) -> list[Source]:
        with get_db() as conn:
            rows = conn.execute("SELECT * FROM sources ORDER BY subject_id").fetchall()
        return [self._row_to_source(dict(r)) for r in rows]

    def insert(self, source: Source) -> None:
        errors = source.validate()
        if errors:
            raise ValueError(f"Invalid source: {errors}")
        with get_db() as conn:
            conn.execute(
                """INSERT INTO sources (
                    source_id, title, subject_id, medium, board, curriculum,
                    class_level, edition, publisher, source_uri, rights_status,
                    rights_notes, file_sha256, ingestion_status, created_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    source.source_id,
                    source.title,
                    source.subject_id,
                    source.medium,
                    source.board,
                    source.curriculum,
                    source.class_level,
                    source.edition,
                    source.publisher,
                    source.source_uri,
                    source.rights_status.value,
                    source.rights_notes,
                    source.file_sha256,
                    source.ingestion_status.value,
                    source.created_at.isoformat(),
                ),
            )

    def update_ingestion_status(self, source_id: str, status: IngestionStatus) -> bool:
        with get_db() as conn:
            cursor = conn.execute(
                "UPDATE sources SET ingestion_status = ? WHERE source_id = ?",
                (status.value, source_id),
            )
            return cursor.rowcount > 0

    @staticmethod
    def _row_to_source(d: dict) -> Source:
        created_at = d.get("created_at")
        if isinstance(created_at, str):
            created_at = datetime.fromisoformat(created_at)
        elif not isinstance(created_at, datetime):
            created_at = datetime.utcnow()

        return Source(
            source_id=d["source_id"],
            title=d["title"],
            subject_id=d["subject_id"],
            medium=d.get("medium", "English"),
            board=d.get("board", "Tamil Nadu State Board"),
            curriculum=d.get("curriculum", "Samacheer Kalvi"),
            class_level=int(d.get("class_level", 10)),
            edition=d["edition"],
            publisher=d.get("publisher", ""),
            rights_status=RightsStatus(d.get("rights_status", RightsStatus.UNKNOWN.value)),
            rights_notes=d.get("rights_notes", ""),
            ingestion_status=IngestionStatus(
                d.get("ingestion_status", IngestionStatus.PENDING.value)
            ),
            created_at=created_at,
            source_uri=d.get("source_uri"),
            file_sha256=d.get("file_sha256"),
        )


class ChapterRepository:

    def list_by_source(self, source_id: str) -> list[dict]:
        with get_db() as conn:
            rows = conn.execute(
                "SELECT * FROM chapters WHERE source_id = ? ORDER BY chapter_number",
                (source_id,),
            ).fetchall()
        return [dict(r) for r in rows]

    def get_by_id(self, chapter_id: str) -> Optional[dict]:
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM chapters WHERE chapter_id = ?", (chapter_id,)
            ).fetchone()
        return dict(row) if row else None

    def insert(self, chapter: dict) -> None:
        required = {"chapter_id", "source_id", "subject_id", "chapter_number", "title"}
        missing = required - set(chapter.keys())
        if missing:
            raise ValueError(f"Chapter missing required fields: {missing}")
        with get_db() as conn:
            conn.execute(
                """INSERT OR REPLACE INTO chapters (
                    chapter_id, source_id, subject_id, chapter_number,
                    title, start_pdf_page, end_pdf_page, status
                ) VALUES (?,?,?,?,?,?,?,?)""",
                (
                    chapter["chapter_id"],
                    chapter["source_id"],
                    chapter["subject_id"],
                    int(chapter["chapter_number"]),
                    chapter["title"],
                    int(chapter.get("start_pdf_page", 0)),
                    int(chapter.get("end_pdf_page", 0)),
                    chapter.get("status", "pending"),
                ),
            )
