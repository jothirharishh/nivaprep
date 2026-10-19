"""
backend/repositories/question_repository.py
CRUD for questions. All DB access goes through this module.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Optional

from ..models.question import (
    Difficulty,
    Question,
    QuestionOption,
    QuestionOrigin,
    QuestionType,
    ReviewStatus,
    SourceRef,
)
from .db import get_db


class QuestionRepository:

    # ── Reads ─────────────────────────────────────────────────────────────────

    def get_by_id(self, question_id: str) -> Optional[Question]:
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM questions WHERE question_id = ?", (question_id,)
            ).fetchone()
        return self._row_to_question(row) if row else None

    def list_verified(
        self,
        subject_id: str | None = None,
        chapter_id: str | None = None,
        origin: str | None = None,
        limit: int = 50,
    ) -> list[Question]:
        if limit < 1 or limit > 200:
            raise ValueError("limit must be between 1 and 200")
        params: list = [ReviewStatus.VERIFIED.value]
        where = ["review_status = ?"]
        if subject_id:
            where.append("subject_id = ?")
            params.append(subject_id)
        if chapter_id:
            where.append("chapter_id = ?")
            params.append(chapter_id)
        if origin:
            if origin not in [e.value for e in QuestionOrigin]:
                raise ValueError(f"Invalid origin filter: {origin!r}")
            where.append("origin = ?")
            params.append(origin)
        params.append(limit)
        sql = f"SELECT * FROM questions WHERE {' AND '.join(where)} ORDER BY created_at LIMIT ?"
        with get_db() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [self._row_to_question(r) for r in rows]

    def list_by_review_status(self, status: ReviewStatus) -> list[Question]:
        with get_db() as conn:
            rows = conn.execute(
                "SELECT * FROM questions WHERE review_status = ? ORDER BY created_at",
                (status.value,),
            ).fetchall()
        return [self._row_to_question(r) for r in rows]

    def count_by_chapter(self, subject_id: str | None = None) -> dict[str, int]:
        """Return a mapping of chapter_id -> verified question count."""
        sql = "SELECT chapter_id, COUNT(*) as cnt FROM questions WHERE review_status = ?"
        params: list = [ReviewStatus.VERIFIED.value]
        if subject_id:
            sql += " AND subject_id = ?"
            params.append(subject_id)
        sql += " GROUP BY chapter_id"
        with get_db() as conn:
            rows = conn.execute(sql, params).fetchall()
        return {r["chapter_id"]: r["cnt"] for r in rows}

    # ── Writes ────────────────────────────────────────────────────────────────

    def insert(self, question: Question) -> None:
        errors = question.validate()
        if errors:
            raise ValueError(f"Invalid question: {errors}")
        with get_db() as conn:
            conn.execute(
                """INSERT INTO questions (
                    question_id, subject_id, source_id, chapter_id, chapter_title,
                    language, origin, question_type, question_text, options_json,
                    correct_option_id, explanation, source_refs_json, difficulty,
                    review_status, review_notes, reviewed_by, reviewed_at,
                    model_provider, model_id, prompt_version, content_version,
                    created_at, updated_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                self._question_to_row(question),
            )

    def update_review_status(
        self,
        question_id: str,
        new_status: ReviewStatus,
        reviewer: str,
        notes: str | None = None,
    ) -> bool:
        """Update review status. Returns True if a row was updated."""
        now = datetime.now(timezone.utc).isoformat()
        with get_db() as conn:
            cursor = conn.execute(
                """UPDATE questions
                   SET review_status = ?, reviewed_by = ?, reviewed_at = ?,
                       review_notes = ?, updated_at = ?
                   WHERE question_id = ?""",
                (new_status.value, reviewer, now, notes, now, question_id),
            )
            return cursor.rowcount > 0

    def update_content(self, question: Question) -> bool:
        """
        Update question text / options / answer. Increments content_version.
        Any answer change must be reviewed again — status is reset to pending_review.
        """
        errors = question.validate()
        if errors:
            raise ValueError(f"Invalid question update: {errors}")
        now = datetime.now(timezone.utc).isoformat()
        with get_db() as conn:
            cursor = conn.execute(
                """UPDATE questions
                   SET question_text = ?, options_json = ?, correct_option_id = ?,
                       explanation = ?, source_refs_json = ?, difficulty = ?,
                       review_status = ?, content_version = content_version + 1,
                       updated_at = ?
                   WHERE question_id = ?""",
                (
                    question.question_text,
                    json.dumps([o.to_dict() for o in question.options]),
                    question.correct_option_id,
                    question.explanation,
                    json.dumps([r.to_dict() for r in question.source_refs]),
                    question.difficulty.value,
                    ReviewStatus.PENDING_REVIEW.value,  # Force re-review after edit
                    now,
                    question.question_id,
                ),
            )
            return cursor.rowcount > 0

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _question_to_row(q: Question) -> tuple:
        return (
            q.question_id,
            q.subject_id,
            q.source_id,
            q.chapter_id,
            q.chapter_title,
            q.language,
            q.origin.value,
            q.question_type.value,
            q.question_text,
            json.dumps([o.to_dict() for o in q.options]),
            q.correct_option_id,
            q.explanation,
            json.dumps([r.to_dict() for r in q.source_refs]),
            q.difficulty.value,
            q.review_status.value,
            q.review_notes,
            q.reviewed_by,
            q.reviewed_at.isoformat() if q.reviewed_at else None,
            q.model_provider,
            q.model_id,
            q.prompt_version,
            q.content_version,
            q.created_at.isoformat(),
            q.updated_at.isoformat(),
        )

    @staticmethod
    def _row_to_question(row: sqlite3.Row | dict) -> Question:  # type: ignore[name-defined]
        import sqlite3  # local import to avoid circular

        d = dict(row) if isinstance(row, sqlite3.Row) else row
        return Question(
            question_id=d["question_id"],
            subject_id=d["subject_id"],
            source_id=d["source_id"],
            chapter_id=d["chapter_id"],
            chapter_title=d.get("chapter_title", ""),
            language=d.get("language", "en"),
            origin=QuestionOrigin(d["origin"]),
            question_type=QuestionType(d.get("question_type", QuestionType.MCQ.value)),
            question_text=d["question_text"],
            options=[QuestionOption.from_dict(o) for o in json.loads(d["options_json"])],
            correct_option_id=d["correct_option_id"],
            explanation=d.get("explanation", ""),
            source_refs=[SourceRef.from_dict(r) for r in json.loads(d["source_refs_json"])],
            difficulty=Difficulty(d.get("difficulty", Difficulty.UNKNOWN.value)),
            review_status=ReviewStatus(d["review_status"]),
            review_notes=d.get("review_notes"),
            reviewed_by=d.get("reviewed_by"),
            reviewed_at=datetime.fromisoformat(d["reviewed_at"]) if d.get("reviewed_at") else None,
            model_provider=d.get("model_provider"),
            model_id=d.get("model_id"),
            prompt_version=d.get("prompt_version"),
            content_version=int(d.get("content_version", 1)),
            created_at=datetime.fromisoformat(d["created_at"]),
            updated_at=datetime.fromisoformat(d["updated_at"]),
        )
