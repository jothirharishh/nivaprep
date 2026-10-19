"""
backend/repositories/progress_repository.py
Local student attempt tracking — no personal data stored.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
import uuid

from .db import get_db


class ProgressRepository:

    def record_attempt(
        self,
        local_student_id: str,
        question_id: str,
        selected_option_id: Optional[str],
        is_correct: bool,
        mode: str,
        question_content_version: int = 1,
    ) -> str:
        """Insert an attempt record and return the new attempt_id."""
        if mode not in ("practice", "exam", "mistake_review"):
            raise ValueError(f"Invalid mode: {mode!r}")
        attempt_id = str(uuid.uuid4())
        now = datetime.now(timezone.utc).isoformat()
        with get_db() as conn:
            conn.execute(
                """INSERT INTO student_attempts (
                    attempt_id, local_student_id, question_id,
                    selected_option_id, is_correct, mode,
                    attempted_at, question_content_version
                ) VALUES (?,?,?,?,?,?,?,?)""",
                (
                    attempt_id,
                    local_student_id,
                    question_id,
                    selected_option_id,
                    1 if is_correct else 0,
                    mode,
                    now,
                    question_content_version,
                ),
            )
        return attempt_id

    def get_incorrect_question_ids(self, local_student_id: str) -> list[str]:
        """
        Return IDs of questions the student has answered incorrectly and
        never subsequently answered correctly.
        """
        with get_db() as conn:
            rows = conn.execute(
                """SELECT DISTINCT question_id FROM student_attempts
                   WHERE local_student_id = ? AND is_correct = 0
                   AND question_id NOT IN (
                       SELECT DISTINCT question_id FROM student_attempts
                       WHERE local_student_id = ? AND is_correct = 1
                   )
                   ORDER BY attempted_at DESC""",
                (local_student_id, local_student_id),
            ).fetchall()
        return [r["question_id"] for r in rows]

    def get_chapter_stats(
        self, local_student_id: str, subject_id: str | None = None
    ) -> list[dict]:
        """Aggregate stats per chapter for a student."""
        params: list = [local_student_id]
        extra_where = ""
        if subject_id:
            extra_where = " AND q.subject_id = ?"
            params.append(subject_id)
        with get_db() as conn:
            rows = conn.execute(
                f"""SELECT q.chapter_id, q.subject_id,
                       COUNT(*) AS total_attempts,
                       SUM(a.is_correct) AS correct_count
                   FROM student_attempts a
                   JOIN questions q ON a.question_id = q.question_id
                   WHERE a.local_student_id = ?{extra_where}
                   GROUP BY q.chapter_id, q.subject_id
                   ORDER BY q.subject_id, q.chapter_id""",
                params,
            ).fetchall()
        return [dict(r) for r in rows]

    def get_recent_sessions(self, local_student_id: str, limit: int = 10) -> list[dict]:
        with get_db() as conn:
            rows = conn.execute(
                """SELECT q.chapter_id, q.subject_id,
                       COUNT(*) AS questions_attempted,
                       SUM(a.is_correct) AS correct_count,
                       MAX(a.attempted_at) AS last_attempted_at
                   FROM student_attempts a
                   JOIN questions q ON a.question_id = q.question_id
                   WHERE a.local_student_id = ?
                   GROUP BY q.chapter_id, q.subject_id
                   ORDER BY last_attempted_at DESC
                   LIMIT ?""",
                (local_student_id, limit),
            ).fetchall()
        return [dict(r) for r in rows]

    def get_student_summary(self, local_student_id: str) -> dict:
        """Overall aggregate statistics for a student."""
        with get_db() as conn:
            row = conn.execute(
                """SELECT
                       COUNT(*) AS total_attempts,
                       COALESCE(SUM(is_correct), 0) AS correct_attempts
                   FROM student_attempts
                   WHERE local_student_id = ?""",
                (local_student_id,),
            ).fetchone()
        total = row["total_attempts"] if row else 0
        correct = row["correct_attempts"] if row else 0
        accuracy = (correct / total) if total > 0 else 0.0
        return {
            "total_attempts": total,
            "correct_attempts": correct,
            "accuracy": accuracy,
        }

    def clear_attempts(self, local_student_id: str | None = None) -> int:
        """Clear attempts for a student or all students (privacy feature)."""
        with get_db() as conn:
            if local_student_id:
                cursor = conn.execute(
                    "DELETE FROM student_attempts WHERE local_student_id = ?",
                    (local_student_id,),
                )
            else:
                cursor = conn.execute("DELETE FROM student_attempts")
            return cursor.rowcount

