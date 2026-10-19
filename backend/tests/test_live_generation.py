"""
backend/tests/test_live_generation.py
Unit and endpoint validation tests for the live question generation route.
"""
from __future__ import annotations

import pytest
from unittest.mock import patch, MagicMock

from backend.app import create_app
from backend.repositories.db import init_db, set_database_path
from backend.rag.generator import GroqError
from backend.api.live_generation import _get_existing_questions, _get_diverse_passages


@pytest.fixture(scope="function")
def app(tmp_path, monkeypatch):
    db_path = str(tmp_path / "test_live.db")
    monkeypatch.setenv("GROQ_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_API_KEY", "test-admin")
    monkeypatch.setenv("FLASK_SECRET_KEY", "test-secret")
    monkeypatch.setenv("DATABASE_PATH", db_path)

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


class TestLiveGenerationEndpoint:
    def test_non_json_body_returns_400(self, client):
        r = client.post("/v1/questions/generate", data="not a json", content_type="text/plain")
        assert r.status_code == 400
        assert "Request body must be JSON" in r.get_json()["error"]

    def test_missing_subject_id_returns_400(self, client):
        r = client.post("/v1/questions/generate", json={"chapter_id": "ch_01"})
        assert r.status_code == 400
        assert "subject_id is required" in r.get_json()["error"]

    def test_unknown_subject_id_returns_400(self, client):
        r = client.post("/v1/questions/generate", json={"subject_id": "astronomy", "chapter_id": "ch_01"})
        assert r.status_code == 400
        assert "Unknown subject_id" in r.get_json()["error"]

    def test_missing_chapter_id_returns_400(self, client):
        r = client.post("/v1/questions/generate", json={"subject_id": "science"})
        assert r.status_code == 400
        assert "chapter_id is required" in r.get_json()["error"]

    def test_get_existing_questions_empty_db(self, app):
        q_texts, used_pids = _get_existing_questions("science", "sci_ch01", [])
        assert q_texts == []
        assert used_pids == set()

    def test_get_diverse_passages_fallback_retriever(self, app):
        mock_retriever = MagicMock()
        mock_retriever.retrieve.return_value = [
            {"passage_id": "p1", "text": "Newton's first law."},
            {"passage_id": "p2", "text": "Newton's second law."},
            {"passage_id": "p3", "text": "Newton's third law."},
        ]
        passages = _get_diverse_passages(
            subject_id="science",
            chapter_id="sci_ch01",
            chapter_title="Laws of Motion",
            used_passage_ids=set(),
            retriever=mock_retriever,
            target_count=3,
        )
        assert len(passages) == 3
        assert passages[0]["passage_id"] == "p1"

    @patch("backend.api.live_generation._get_diverse_passages")
    @patch("backend.api.live_generation.generate_mcq")
    def test_generate_live_success(self, mock_gen, mock_passages, client):
        mock_passages.return_value = [
            {
                "passage_id": "pas_001",
                "pdf_page_index": 5,
                "printed_page_label": "12",
                "text": "The SI unit of electric current is the ampere.",
            }
        ]
        mock_gen.return_value = {
            "abstained": False,
            "question_text": "What is the SI unit of electric current?",
            "options": [
                {"option_id": "A", "text": "Ampere"},
                {"option_id": "B", "text": "Volt"},
                {"option_id": "C", "text": "Ohm"},
                {"option_id": "D", "text": "Watt"},
            ],
            "correct_option_id": "A",
            "explanation": "Electric current is measured in amperes (A).",
            "source_passage_ids": ["pas_001"],
            "difficulty": "medium",
        }

        r = client.post(
            "/v1/questions/generate",
            json={"subject_id": "science", "chapter_id": "sci_ch04"},
        )
        assert r.status_code == 200
        data = r.get_json()
        assert data["question_text"] == "What is the SI unit of electric current?"
        assert data["correct_option_id"] == "A"
        assert len(data["options"]) == 4
        assert data["review_status"] == "live"
        assert data["origin"] == "ai_generated"
        assert len(data["source_refs"]) == 1

    @patch("backend.api.live_generation._get_diverse_passages")
    @patch("backend.api.live_generation.generate_mcq")
    def test_generate_live_groq_error(self, mock_gen, mock_passages, client):
        mock_passages.return_value = [{"passage_id": "p1", "text": "sample"}]
        mock_gen.side_effect = GroqError("Service rate limit exceeded")

        r = client.post(
            "/v1/questions/generate",
            json={"subject_id": "science", "chapter_id": "sci_ch04"},
        )
        assert r.status_code == 503
        data = r.get_json()
        assert "LLM service unavailable" in data["error"]

    @patch("backend.api.live_generation._get_diverse_passages")
    @patch("backend.api.live_generation.generate_mcq")
    def test_generate_live_abstention(self, mock_gen, mock_passages, client):
        mock_passages.return_value = [{"passage_id": "p1", "text": "sample"}]
        mock_gen.return_value = {
            "abstained": True,
            "reason": "The selected passages do not support a valid question.",
        }

        r = client.post(
            "/v1/questions/generate",
            json={"subject_id": "science", "chapter_id": "sci_ch04"},
        )
        assert r.status_code == 200
        data = r.get_json()
        assert data["abstained"] is True
