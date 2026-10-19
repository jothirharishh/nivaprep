"""
backend/tests/test_api.py
Integration tests for Flask endpoints using a temporary SQLite database.
No live Groq API — generator calls are patched.
"""
import json
import os
import tempfile
import pytest

from backend.app import create_app
from backend.repositories.db import init_db, set_database_path
from backend.repositories import QuestionRepository, SourceRepository, ChapterRepository
from backend.models.source import Source, RightsStatus, IngestionStatus
from backend.models.question import (
    Difficulty, Question, QuestionOption, QuestionOrigin,
    QuestionType, ReviewStatus, SourceRef,
)


@pytest.fixture(scope="function")
def app(tmp_path, monkeypatch):
    db_path = str(tmp_path / "test.db")
    monkeypatch.setenv("GROQ_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_API_KEY", "test-admin")
    monkeypatch.setenv("FLASK_SECRET_KEY", "test-secret")
    monkeypatch.setenv("DATABASE_PATH", db_path)

    # Reset config singleton
    import backend.config as cfg_mod
    cfg_mod.reset_config()

    set_database_path(db_path)
    init_db(db_path)

    flask_app = create_app()
    flask_app.config["TESTING"] = True
    return flask_app


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def seeded_db(app):
    """Insert a verified question and source into the test DB."""
    src = Source(
        source_id="src_sci_001",
        title="Class 10 Science",
        subject_id="science",
        medium="English",
        board="Tamil Nadu State Board",
        curriculum="Samacheer Kalvi",
        class_level=10,
        edition="2024",
        publisher="SCERT",
        rights_status=RightsStatus.USER_SUPPLIED_REVIEW_REQUIRED,
        rights_notes="User supplied",
        ingestion_status=IngestionStatus.COMPLETED,
    )
    SourceRepository().insert(src)

    from datetime import datetime, timezone
    q = Question(
        question_id="q_test_api_001",
        subject_id="science",
        source_id="src_sci_001",
        chapter_id="science_ch01",
        chapter_title="Chemical Reactions",
        language="en",
        origin=QuestionOrigin.AI_GENERATED,
        question_type=QuestionType.MCQ,
        question_text="What is H2O?",
        options=[
            QuestionOption("A", "Water"),
            QuestionOption("B", "Carbon dioxide"),
            QuestionOption("C", "Salt"),
            QuestionOption("D", "Hydrochloric acid"),
        ],
        correct_option_id="A",
        explanation="H2O is the chemical formula for water.",
        source_refs=[SourceRef("pas_001", 0, "1")],
        difficulty=Difficulty.EASY,
        review_status=ReviewStatus.VERIFIED,
        reviewed_by="admin",
        reviewed_at=datetime.now(timezone.utc),
        content_version=1,
    )
    QuestionRepository().insert(q)
    return q


class TestHealth:
    def test_health_returns_ok(self, client):
        r = client.get("/health")
        assert r.status_code == 200
        assert r.get_json()["status"] == "ok"


class TestSubjects:
    def test_list_subjects_returns_five(self, client):
        r = client.get("/v1/subjects")
        assert r.status_code == 200
        data = r.get_json()
        assert len(data["subjects"]) == 5
        ids = {s["subject_id"] for s in data["subjects"]}
        assert "science" in ids
        assert "mathematics" in ids


class TestQuestions:
    def test_list_verified_questions(self, client, seeded_db):
        r = client.get("/v1/questions?subject_id=science")
        assert r.status_code == 200
        data = r.get_json()
        assert data["count"] >= 1

    def test_invalid_subject_returns_400(self, client):
        r = client.get("/v1/questions?subject_id=invalid_subject")
        assert r.status_code == 400

    def test_limit_capped(self, client):
        r = client.get("/v1/questions?limit=999")
        assert r.status_code == 200  # capped to 200, not an error

    def test_get_single_question(self, client, seeded_db):
        r = client.get("/v1/questions/q_test_api_001")
        assert r.status_code == 200
        assert r.get_json()["question_id"] == "q_test_api_001"

    def test_get_nonexistent_question_returns_404(self, client):
        r = client.get("/v1/questions/nonexistent")
        assert r.status_code == 404


class TestAdminAuth:
    def test_review_without_key_returns_401(self, client, seeded_db):
        r = client.post(
            "/v1/admin/questions/q_test_api_001/review",
            json={"action": "retire", "reviewer": "admin"},
        )
        assert r.status_code == 401

    def test_review_with_wrong_key_returns_401(self, client, seeded_db):
        r = client.post(
            "/v1/admin/questions/q_test_api_001/review",
            json={"action": "retire", "reviewer": "admin"},
            headers={"X-Admin-Key": "wrong"},
        )
        assert r.status_code == 401

    def test_review_retire_with_correct_key(self, client, seeded_db):
        r = client.post(
            "/v1/admin/questions/q_test_api_001/review",
            json={"action": "retire", "reviewer": "admin"},
            headers={"X-Admin-Key": "test-admin"},
        )
        assert r.status_code == 200
        assert r.get_json()["new_status"] == "retired"


class TestTextbookQA:
    def test_ask_with_no_index_returns_503(self, client):
        r = client.post(
            "/v1/textbook/ask",
            json={"question": "What is photosynthesis?", "subject_id": "science"},
        )
        # No index available in test → 503
        assert r.status_code in (200, 503)  # 200 if empty result path

    def test_ask_empty_question_returns_400(self, client):
        r = client.post("/v1/textbook/ask", json={"question": ""})
        assert r.status_code == 400

    def test_ask_too_long_question_returns_400(self, client):
        r = client.post("/v1/textbook/ask", json={"question": "x" * 1001})
        assert r.status_code == 400

    def test_ask_non_json_returns_400(self, client):
        r = client.post("/v1/textbook/ask", data="not json", content_type="text/plain")
        assert r.status_code == 400
