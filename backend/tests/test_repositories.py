"""
backend/tests/test_repositories.py
Unit tests for SourceRepository, ChapterRepository, and ProgressRepository.
"""
from datetime import datetime, timezone
import pytest

from backend.repositories.db import init_db, set_database_path
from backend.repositories.source_repository import SourceRepository, ChapterRepository
from backend.repositories.progress_repository import ProgressRepository
from backend.models.source import Source, RightsStatus, IngestionStatus


@pytest.fixture
def clean_db(tmp_path):
    db_file = str(tmp_path / "repo_test.db")
    set_database_path(db_file)
    init_db(db_file)
    return db_file


def test_source_repository_crud(clean_db):
    repo = SourceRepository()
    now = datetime.now(timezone.utc)
    source = Source(
        source_id="src_sci_10_2024",
        title="Class 10 Science",
        subject_id="science",
        edition="2024",
        rights_status=RightsStatus.PUBLIC_TERMS_REVIEWED,
        rights_notes="TNSCERT public release",
        created_at=now,
    )

    repo.insert(source)
    fetched = repo.get_by_id("src_sci_10_2024")
    assert fetched is not None
    assert fetched.title == "Class 10 Science"
    assert fetched.subject_id == "science"
    assert fetched.rights_status == RightsStatus.PUBLIC_TERMS_REVIEWED

    all_sources = repo.list_all()
    assert len(all_sources) == 1
    assert all_sources[0].source_id == "src_sci_10_2024"

    # Update ingestion status
    updated = repo.update_ingestion_status("src_sci_10_2024", IngestionStatus.COMPLETED)
    assert updated is True
    assert repo.get_by_id("src_sci_10_2024").ingestion_status == IngestionStatus.COMPLETED


def test_chapter_repository_crud(clean_db):
    src_repo = SourceRepository()
    now = datetime.now(timezone.utc)
    src_repo.insert(
        Source(
            source_id="src_sci_10_2024",
            title="Class 10 Science",
            subject_id="science",
            edition="2024",
            rights_status=RightsStatus.PUBLIC_TERMS_REVIEWED,
            created_at=now,
        )
    )

    chap_repo = ChapterRepository()
    chapter = {
        "chapter_id": "sci_ch01",
        "source_id": "src_sci_10_2024",
        "subject_id": "science",
        "chapter_number": 1,
        "title": "Laws of Motion",
        "start_pdf_page": 1,
        "end_pdf_page": 20,
        "status": "ready",
    }
    chap_repo.insert(chapter)

    fetched = chap_repo.get_by_id("sci_ch01")
    assert fetched is not None
    assert fetched["title"] == "Laws of Motion"
    assert fetched["chapter_number"] == 1

    by_source = chap_repo.list_by_source("src_sci_10_2024")
    assert len(by_source) == 1
    assert by_source[0]["chapter_id"] == "sci_ch01"

    # Missing fields raises ValueError
    with pytest.raises(ValueError, match="Chapter missing required fields"):
        chap_repo.insert({"chapter_id": "bad"})


def test_progress_repository(clean_db):
    from backend.repositories.question_repository import QuestionRepository
    from backend.models.question import (
        Question, QuestionOption, QuestionOrigin, QuestionType, ReviewStatus, SourceRef,
    )

    q_repo = QuestionRepository()
    for qid in ["q_001", "q_002", "q_003"]:
        q_repo.insert(
            Question(
                question_id=qid,
                subject_id="science",
                source_id="src_sci_10_2024",
                chapter_id="sci_ch01",
                chapter_title="Laws of Motion",
                origin=QuestionOrigin.TEXTBOOK,
                question_type=QuestionType.MCQ,
                question_text=f"Question text for {qid}",
                options=[
                    QuestionOption(option_id="opt_a", text="Option A"),
                    QuestionOption(option_id="opt_b", text="Option B"),
                    QuestionOption(option_id="opt_c", text="Option C"),
                    QuestionOption(option_id="opt_d", text="Option D"),
                ],
                correct_option_id="opt_a",
                explanation="Valid explanation for testing.",
                source_refs=[SourceRef("pas_001", 0, "1")],
                review_status=ReviewStatus.VERIFIED,
                reviewed_by="teacher",
                reviewed_at=datetime.now(timezone.utc),
            )
        )

    prog_repo = ProgressRepository()
    student_id = "student_test_1"

    # Record 3 attempts (2 correct, 1 wrong)
    prog_repo.record_attempt(
        local_student_id=student_id,
        question_id="q_001",
        selected_option_id="opt_a",
        is_correct=True,
        mode="practice",
        question_content_version=1,
    )
    prog_repo.record_attempt(
        local_student_id=student_id,
        question_id="q_002",
        selected_option_id="opt_b",
        is_correct=False,
        mode="practice",
        question_content_version=1,
    )
    prog_repo.record_attempt(
        local_student_id=student_id,
        question_id="q_003",
        selected_option_id="opt_c",
        is_correct=True,
        mode="exam",
        question_content_version=1,
    )

    summary = prog_repo.get_student_summary(student_id)
    assert summary["total_attempts"] == 3
    assert summary["correct_attempts"] == 2
    assert summary["accuracy"] == pytest.approx(2 / 3, rel=1e-2)

    mistakes = prog_repo.get_incorrect_question_ids(student_id)
    assert len(mistakes) == 1
    assert mistakes[0] == "q_002"

    stats = prog_repo.get_chapter_stats(student_id)
    assert len(stats) == 1
    assert stats[0]["chapter_id"] == "sci_ch01"
    assert stats[0]["total_attempts"] == 3
    assert stats[0]["correct_count"] == 2

    # Test clear_attempts
    cleared = prog_repo.clear_attempts(student_id)
    assert cleared == 3
    assert prog_repo.get_student_summary(student_id)["total_attempts"] == 0
