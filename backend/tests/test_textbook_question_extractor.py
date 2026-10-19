"""
backend/tests/test_textbook_question_extractor.py
Unit tests for the textbook PDF question extractor and clean_pdf_text helper.
"""
import pytest
from pathlib import Path
from backend.ingestion.textbook_question_extractor import (
    clean_pdf_text,
    TextbookQuestionExtractor,
    ExtractedMCQ,
)
from backend.models.question import QuestionOrigin, ReviewStatus
from backend.repositories.question_repository import QuestionRepository
from backend.repositories.source_repository import ChapterRepository


def test_clean_pdf_text():
    raw = "TEXTBOOK EVALUATION\n1)\tInertia of a body\u2002depends on\r\n"
    cleaned = clean_pdf_text(raw)
    assert "TEXTBOOK EVALUATION" not in cleaned
    assert "Inertia of a body depends on" in cleaned


from backend.repositories.db import init_db, set_database_path


@pytest.fixture
def tmp_db(tmp_path):
    db_path = tmp_path / "test_extract.db"
    set_database_path(db_path)
    init_db(db_path)
    return db_path


def test_extracted_mcq_persistence(tmp_db):
    extractor = TextbookQuestionExtractor()
    mcq = ExtractedMCQ(
        question_number=99,
        question_text="Sample physics test question on Newton's laws?",
        options={
            "A": "Option Alpha",
            "B": "Option Beta",
            "C": "Option Gamma",
            "D": "Option Delta",
        },
        correct_option_id="B",
        explanation="Newton's laws provide the foundational mechanics.",
        subject_id="science",
        source_id="src_tn_sci_10_2024",
        chapter_id="sci_ch01",
        chapter_title="Chapter 1: Laws of Motion",
        pdf_page_index=20,
        printed_page_label="13",
    )

    inserted, skipped, errors = extractor.persist_extracted_mcqs([mcq])
    assert inserted == 1
    assert skipped == 0
    assert len(errors) == 0

    # Retrieve and verify
    q_repo = QuestionRepository()
    stored = q_repo.get_by_id("q_sci_ch01_099")
    assert stored is not None
    assert stored.origin == QuestionOrigin.TEXTBOOK
    assert stored.review_status == ReviewStatus.VERIFIED
    assert stored.correct_option_id == "B"
    assert len(stored.options) == 4
    assert len(stored.source_refs) == 1
    assert stored.source_refs[0].pdf_page_index == 20

    # Test idempotence / duplicate skip
    inserted2, skipped2, errors2 = extractor.persist_extracted_mcqs([mcq])
    assert inserted2 == 0
    assert skipped2 == 1


def test_extract_science_ch1_from_real_pdf():
    pdf_path = Path("en/Class_10_Science_English_Medium-2024_Edition-www.tntextbooks.in.pdf")
    if not pdf_path.exists():
        pytest.skip("Science PDF not found in en/ folder")

    extractor = TextbookQuestionExtractor()
    mcqs = extractor.extract_science_chapter1(pdf_path)
    assert len(mcqs) == 10
    q1 = mcqs[0]
    assert q1.question_number == 1
    assert "Inertia" in q1.question_text
    assert q1.correct_option_id == "C"
    assert len(q1.options) == 4
    assert "A" in q1.options and "D" in q1.options


def test_extract_mathematics_ch1_from_real_pdf():
    pdf_path = Path("en/Class_10_Mathematics_English_Medium-2025_Edition-www.tntextbooks.in.pdf")
    if not pdf_path.exists():
        pytest.skip("Mathematics PDF not found in en/ folder")

    extractor = TextbookQuestionExtractor()
    mcqs = extractor.extract_mathematics_chapter1(pdf_path)
    assert len(mcqs) >= 15
    q1 = mcqs[0]
    assert q1.question_number == 1
    assert q1.correct_option_id == "C"
    assert "n(A" in q1.question_text or "n A" in q1.question_text
