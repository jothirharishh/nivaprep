"""
backend/tests/test_admin_generation.py
Tests for admin generation job endpoint with mocked LLM and retriever.
"""
import json
import pytest
from unittest.mock import patch

from backend.app import create_app
from backend.repositories.db import init_db, set_database_path
import backend.config as cfg_mod


@pytest.fixture
def app(tmp_path, monkeypatch):
    db_path = str(tmp_path / "admin_test.db")
    monkeypatch.setenv("GROQ_API_KEY", "test-key")
    monkeypatch.setenv("ADMIN_API_KEY", "secret-admin-key")
    monkeypatch.setenv("FLASK_SECRET_KEY", "secret-key")
    monkeypatch.setenv("DATABASE_PATH", db_path)

    cfg_mod.reset_config()
    set_database_path(db_path)
    init_db(db_path)

    flask_app = create_app()
    flask_app.config["TESTING"] = True
    return flask_app


@pytest.fixture
def client(app):
    return app.test_client()


def test_generation_job_unauthorized(client):
    r = client.post(
        "/v1/admin/generation-jobs",
        json={"subject_id": "science", "source_id": "src_1", "chapter_id": "sci_ch01"},
    )
    assert r.status_code == 401


def test_generation_job_invalid_input(client):
    headers = {"X-Admin-Key": "secret-admin-key"}
    r = client.post(
        "/v1/admin/generation-jobs",
        json={"subject_id": "invalid_subject", "source_id": "src_1", "chapter_id": "sci_ch01"},
        headers=headers,
    )
    assert r.status_code == 400


def test_generation_job_run_success(client):
    headers = {"X-Admin-Key": "secret-admin-key"}

    fake_passages = [
        {
            "passage_id": "pas_100",
            "source_id": "src_1",
            "subject_id": "science",
            "chapter_id": "sci_ch01",
            "chapter_title": "Laws of Motion",
            "text": "Force equals mass times acceleration (F = ma).",
            "printed_page_label": "4",
        }
    ]

    mock_mcq_response = {
        "abstained": False,
        "question_text": "What is the formula relating force, mass, and acceleration?",
        "options": [
            {"option_id": "A", "text": "F = ma"},
            {"option_id": "B", "text": "F = m/a"},
            {"option_id": "C", "text": "F = a/m"},
            {"option_id": "D", "text": "F = m + a"},
        ],
        "correct_option_id": "A",
        "explanation": "According to Newton's second law, F = ma.",
        "source_passage_ids": ["pas_100"],
        "difficulty": "easy",
        "model_id": "llama-3.3-70b-versatile",
        "prompt_version": "mcq-v1",
    }

    with patch("backend.api.admin_generation._get_retriever") as mock_retriever_fn, \
         patch("backend.api.admin_generation.generate_mcq") as mock_gen_fn:

        mock_retriever = mock_retriever_fn.return_value
        mock_retriever.retrieve.return_value = fake_passages
        mock_gen_fn.return_value = mock_mcq_response

        r = client.post(
            "/v1/admin/generation-jobs",
            json={
                "subject_id": "science",
                "source_id": "src_1",
                "chapter_id": "sci_ch01",
                "requested_count": 1,
            },
            headers=headers,
        )

        assert r.status_code == 201
        data = r.get_json()
        assert "job_id" in data
        job_id = data["job_id"]

        # Fetch job status
        get_res = client.get(f"/v1/admin/generation-jobs/{job_id}", headers=headers)
        assert get_res.status_code == 200
        job_data = get_res.get_json()
        assert job_data["status"] == "completed"
        assert job_data["validation_summary"]["accepted"] == 1
        assert len(job_data["candidate_question_ids"]) == 1
