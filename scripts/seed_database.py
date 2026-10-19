"""
scripts/seed_database.py
Initialises the SQLite database and seeds verified textbook sources, chapters, and questions.
Usage:
    python scripts/seed_database.py [--db-path backend/data/boardmate.db]
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from backend.repositories.db import init_db, set_database_path, get_db
from backend.repositories import QuestionRepository, SourceRepository, ChapterRepository
from backend.models.source import Source, RightsStatus, IngestionStatus
from backend.models.question import (
    Difficulty, Question, QuestionOption, QuestionOrigin,
    QuestionType, ReviewStatus, SourceRef,
)

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger("seed")


def seed_database(db_path: str | None = None) -> None:
    if db_path is None:
        db_path = str(PROJECT_ROOT / "backend" / "data" / "boardmate.db")

    logger.info("Setting database path to: %s", db_path)
    set_database_path(db_path)
    init_db(db_path)

    src_repo = SourceRepository()
    chap_repo = ChapterRepository()
    q_repo = QuestionRepository()

    # ── 1. Seed Sources ────────────────────────────────────────────────────────
    sources_path = PROJECT_ROOT / "data" / "fixtures" / "sample_sources.json"
    if sources_path.exists():
        with open(sources_path, encoding="utf-8") as f:
            sources_data = json.load(f)
        for s in sources_data:
            existing = src_repo.get_by_id(s["source_id"])
            if not existing:
                src_repo.insert(
                    Source(
                        source_id=s["source_id"],
                        title=s["title"],
                        subject_id=s["subject_id"],
                        medium=s.get("medium", "English"),
                        board=s.get("board", "Tamil Nadu State Board"),
                        curriculum=s.get("curriculum", "Samacheer Kalvi"),
                        class_level=int(s.get("class_level", 10)),
                        edition=s["edition"],
                        publisher=s.get("publisher", ""),
                        rights_status=RightsStatus(s.get("rights_status", "public_terms_reviewed")),
                        rights_notes=s.get("rights_notes", ""),
                        ingestion_status=IngestionStatus(s.get("ingestion_status", "completed")),
                    )
                )
                logger.info("Inserted source: %s (%s)", s["title"], s["source_id"])

    # ── 2. Seed Chapters ───────────────────────────────────────────────────────
    chapters = [
        {"chapter_id": "tam_ch01", "source_id": "src_tn_tam_10_2025", "subject_id": "tamil", "chapter_number": 1, "title": "இயல் 1: அன்னை மொழியே"},
        {"chapter_id": "tam_ch02", "source_id": "src_tn_tam_10_2025", "subject_id": "tamil", "chapter_number": 2, "title": "இயல் 2: காற்றே வா"},
        {"chapter_id": "eng_u01", "source_id": "src_tn_eng_10_2024", "subject_id": "english", "chapter_number": 1, "title": "Unit 1: His First Flight"},
        {"chapter_id": "eng_u02", "source_id": "src_tn_eng_10_2024", "subject_id": "english", "chapter_number": 2, "title": "Unit 2: The Night the Ghost Got In"},
        {"chapter_id": "mat_ch01", "source_id": "src_tn_mat_10_2025", "subject_id": "mathematics", "chapter_number": 1, "title": "Chapter 1: Relations and Functions"},
        {"chapter_id": "mat_ch02", "source_id": "src_tn_mat_10_2025", "subject_id": "mathematics", "chapter_number": 2, "title": "Chapter 2: Numbers and Sequences"},
        {"chapter_id": "sci_ch01", "source_id": "src_tn_sci_10_2024", "subject_id": "science", "chapter_number": 1, "title": "Chapter 1: Laws of Motion"},
        {"chapter_id": "sci_ch02", "source_id": "src_tn_sci_10_2024", "subject_id": "science", "chapter_number": 2, "title": "Chapter 2: Optics"},
        {"chapter_id": "soc_his_01", "source_id": "src_tn_soc_10_2025", "subject_id": "social_science", "chapter_number": 1, "title": "History Unit 1: Outbreak of World War I"},
        {"chapter_id": "soc_geo_01", "source_id": "src_tn_soc_10_2025", "subject_id": "social_science", "chapter_number": 2, "title": "Geography Unit 1: India - Location, Relief and Drainage"},
    ]
    for c in chapters:
        c["status"] = "ready"
        chap_repo.insert(c)
    logger.info("Seeded %d chapters across 5 subjects", len(chapters))

    # ── 3. Seed Questions ──────────────────────────────────────────────────────
    questions_path = PROJECT_ROOT / "data" / "fixtures" / "sample_questions.json"
    if questions_path.exists():
        with open(questions_path, encoding="utf-8") as f:
            questions_data = json.load(f)
        for q in questions_data:
            existing = q_repo.get_by_id(q["question_id"])
            if not existing:
                question_obj = Question(
                    question_id=q["question_id"],
                    subject_id=q["subject_id"],
                    source_id=q["source_id"],
                    chapter_id=q["chapter_id"],
                    chapter_title=q["chapter_title"],
                    language=q.get("language", "en"),
                    origin=QuestionOrigin(q.get("origin", "textbook")),
                    question_type=QuestionType(q.get("question_type", "mcq")),
                    question_text=q["question_text"],
                    options=[QuestionOption.from_dict(o) for o in q["options"]],
                    correct_option_id=q["correct_option_id"],
                    explanation=q.get("explanation", ""),
                    source_refs=[SourceRef.from_dict(r) for r in q.get("source_refs", [])],
                    difficulty=Difficulty(q.get("difficulty", "unknown")),
                    review_status=ReviewStatus(q.get("review_status", "verified")),
                    reviewed_by=q.get("reviewed_by", "system"),
                    reviewed_at=datetime.fromisoformat(q["reviewed_at"]) if q.get("reviewed_at") else datetime.now(timezone.utc),
                    content_version=q.get("content_version", 1),
                )
                errors = question_obj.validate()
                if errors:
                    logger.error("Skipping invalid question %s: %s", q["question_id"], errors)
                    continue
                q_repo.insert(question_obj)
                logger.info("Inserted question: %s (%s)", q["question_id"], q["subject_id"])

    verified_questions = q_repo.list_verified(limit=200)
    logger.info("Seeding complete! Database has %d verified questions.", len(verified_questions))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Seed BoardMate database")
    parser.add_argument("--db-path", default=None, help="Path to SQLite database file")
    args = parser.parse_args()
    seed_database(args.db_path)
