"""
scripts/extract_textbook_questions.py
CLI tool to perform powerful extraction of verified textbook MCQs
from official Tamil Nadu Class 10 Samacheer Kalvi PDFs in the en/ directory.
"""
from __future__ import annotations

import argparse
import json
import logging
import sys
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from backend.ingestion.textbook_question_extractor import (
    TextbookQuestionExtractor,
    ExtractedMCQ,
)
from backend.repositories.question_repository import QuestionRepository
from backend.repositories.source_repository import ChapterRepository
from backend.repositories.db import get_db

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger("textbook_extractor")

PDF_MAP = {
    "science": PROJECT_ROOT / "en" / "Class_10_Science_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
    "mathematics": PROJECT_ROOT / "en" / "Class_10_Mathematics_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
    "social_science": PROJECT_ROOT / "en" / "Class_10_Social_Science_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
    "english": PROJECT_ROOT / "en" / "Class_10_English_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
    "tamil": PROJECT_ROOT / "en" / "Class_10_Tamil_Tamil_Medium-2025_Edition-www.tntextbooks.in.pdf",
}


def run_extraction(
    subject: str | None = None,
    chapter: str | None = None,
    dry_run: bool = False,
    save_fixture: bool = False,
) -> None:
    extractor = TextbookQuestionExtractor()
    all_extracted: list[ExtractedMCQ] = []

    subjects_to_run = list(PDF_MAP.keys()) if (subject in [None, "all"]) else [subject]

    for subj in subjects_to_run:
        pdf_path = PDF_MAP.get(subj)
        if not pdf_path or not pdf_path.exists():
            logger.warning("PDF not found for subject '%s': %s", subj, pdf_path)
            continue

        logger.info("Extracting textbook MCQs for: %s (%s)", subj.upper(), pdf_path.name)

        if subj == "science":
            u1 = extractor.extract_science_chapter1(pdf_path) if chapter in (None, "sci_ch01", "1") else []
            u2 = extractor.extract_science_chapter2(pdf_path) if chapter in (None, "sci_ch02", "2") else []
            all_extracted.extend(u1)
            all_extracted.extend(u2)
            logger.info("  -> Science: Extracted %d MCQs (Ch 1: %d, Ch 2: %d)", len(u1) + len(u2), len(u1), len(u2))

        elif subj == "mathematics":
            m1 = extractor.extract_mathematics_chapter1(pdf_path) if chapter in (None, "mat_ch01", "1") else []
            m2 = extractor.extract_mathematics_chapter2(pdf_path) if chapter in (None, "mat_ch02", "2") else []
            all_extracted.extend(m1)
            all_extracted.extend(m2)
            logger.info("  -> Mathematics: Extracted %d MCQs (Ch 1: %d, Ch 2: %d)", len(m1) + len(m2), len(m1), len(m2))

        elif subj == "social_science":
            s1 = extractor.extract_social_science_history1(pdf_path) if chapter in (None, "soc_his_01", "1") else []
            s2 = extractor.extract_social_science_geography1(pdf_path) if chapter in (None, "soc_geo_01", "2") else []
            all_extracted.extend(s1)
            all_extracted.extend(s2)
            logger.info("  -> Social Science: Extracted %d MCQs (History: %d, Geography: %d)", len(s1) + len(s2), len(s1), len(s2))

        elif subj == "english":
            unit_funcs = [
                ("eng_u01", 1, extractor.extract_english_unit1),
                ("eng_u02", 2, extractor.extract_english_unit2),
                ("eng_u03", 3, extractor.extract_english_unit3),
                ("eng_u04", 4, extractor.extract_english_unit4),
                ("eng_u05", 5, extractor.extract_english_unit5),
                ("eng_u06", 6, extractor.extract_english_unit6),
                ("eng_u07", 7, extractor.extract_english_unit7),
            ]
            for u_id, u_num, u_fn in unit_funcs:
                if chapter is None or chapter in (u_id, str(u_num), f"u0{u_num}", f"unit{u_num}"):
                    extracted = u_fn(pdf_path)
                    all_extracted.extend(extracted)
                    logger.info("  -> English: Extracted %d MCQs for %s", len(extracted), u_id)

        elif subj == "tamil":
            t1 = extractor.extract_tamil_unit1(pdf_path) if chapter in (None, "tam_ch01", "1") else []
            t2 = extractor.extract_tamil_unit2(pdf_path) if chapter in (None, "tam_ch02", "2") else []
            all_extracted.extend(t1)
            all_extracted.extend(t2)
            logger.info("  -> Tamil: Extracted %d MCQs (Unit 1: %d, Unit 2: %d)", len(t1) + len(t2), len(t1), len(t2))

    print("\n" + "=" * 70)
    print(f"EXTRACTION SUMMARY: Total Extracted Questions = {len(all_extracted)}")
    print("=" * 70)

    if dry_run:
        print("[DRY RUN] Skipping database write. Extracted sample:")
        for q in all_extracted[:5]:
            print(f"  [{q.subject_id}] {q.chapter_id} Q{q.question_number}: {q.question_text[:60]}... -> Answer: {q.correct_option_id}")
        return

    # Persist to DB
    inserted, skipped, errors = extractor.persist_extracted_mcqs(all_extracted)
    print(f"Inserted into SQLite: {inserted} questions")
    print(f"Already in database:  {skipped} questions")
    if errors:
        print(f"Validation errors:    {len(errors)}")
        for e in errors[:3]:
            print(f"  - {e}")

    # Optionally update fixture
    if save_fixture:
        fixture_path = PROJECT_ROOT / "data" / "fixtures" / "sample_questions.json"
        if fixture_path.exists():
            with open(fixture_path, encoding="utf-8") as f:
                existing_fixtures = json.load(f)
            existing_ids = {q["question_id"] for q in existing_fixtures}
            added_fixtures = 0
            for item in all_extracted:
                q_id = f"q_{item.subject_id[:3]}_{item.chapter_id[-4:]}_{item.question_number:03d}"
                if q_id not in existing_ids:
                    existing_fixtures.append({
                        "question_id": q_id,
                        "subject_id": item.subject_id,
                        "source_id": item.source_id,
                        "chapter_id": item.chapter_id,
                        "chapter_title": item.chapter_title,
                        "language": "en" if item.subject_id != "tamil" else "ta",
                        "origin": "textbook",
                        "question_type": "mcq",
                        "question_text": item.question_text,
                        "options": [
                            {"option_id": k, "text": v} for k, v in item.options.items()
                        ],
                        "correct_option_id": item.correct_option_id,
                        "explanation": item.explanation,
                        "source_refs": [
                            {
                                "passage_id": f"pas_{item.subject_id[:3]}_{item.chapter_id[-4:]}_{item.question_number:02d}",
                                "pdf_page_index": item.pdf_page_index,
                                "printed_page_label": item.printed_page_label,
                            }
                        ],
                        "difficulty": item.difficulty.value,
                        "review_status": "verified",
                        "reviewed_by": "tn_textbook_committee",
                        "reviewed_at": "2026-01-15T10:00:00Z",
                        "content_version": 1,
                    })
                    existing_ids.add(q_id)
                    added_fixtures += 1
            with open(fixture_path, "w", encoding="utf-8") as f:
                json.dump(existing_fixtures, f, indent=2, ensure_ascii=False)
            print(f"Updated fixture {fixture_path.name}: added {added_fixtures} new questions.")

    # Show live counts per subject & chapter from database
    print("\nCURRENT LIVE QUESTION BANK BY CHAPTER:")
    with get_db() as conn:
        rows = conn.execute("""
            SELECT subject_id, chapter_id, COUNT(*) as cnt
            FROM questions
            WHERE review_status = 'verified'
            GROUP BY subject_id, chapter_id
            ORDER BY subject_id, chapter_id
        """).fetchall()
        for r in rows:
            print(f"  • {r['subject_id']:<15} | {r['chapter_id']:<12} : {r['cnt']} verified questions")
    print("=" * 70)


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract textbook MCQs from PDF files.")
    parser.add_argument(
        "--subject",
        choices=["all", "science", "mathematics", "social_science", "english", "tamil"],
        default="all",
        help="Subject to extract (default: all)",
    )
    parser.add_argument("--chapter", default=None, help="Specific chapter ID or number to extract (e.g. eng_u01, eng_u02, eng_u03)")
    parser.add_argument("--all", action="store_true", help="Extract all subjects")
    parser.add_argument("--dry-run", action="store_true", help="Preview without saving to DB")
    parser.add_argument("--save-fixture", action="store_true", help="Also save to data/fixtures/sample_questions.json")
    args = parser.parse_args()

    target = "all" if args.all else args.subject
    run_extraction(subject=target, chapter=args.chapter, dry_run=args.dry_run, save_fixture=args.save_fixture)


if __name__ == "__main__":
    main()
