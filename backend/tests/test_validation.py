"""
backend/tests/test_validation.py
Unit tests for RAG output validation — no live Groq API.
"""
import json
import pytest

from backend.rag.validation import (
    ValidationError,
    validate_mcq_response,
    validate_qa_response,
    _parse_json,
)

KNOWN_IDS = {"pas_001", "pas_002"}

VALID_MCQ = {
    "abstained": False,
    "question_text": "What is photosynthesis?",
    "options": [
        {"option_id": "A", "text": "Process of making food"},
        {"option_id": "B", "text": "Process of breathing"},
        {"option_id": "C", "text": "Process of excretion"},
        {"option_id": "D", "text": "Process of reproduction"},
    ],
    "correct_option_id": "A",
    "explanation": "Photosynthesis is the process by which plants make food using sunlight.",
    "source_passage_ids": ["pas_001"],
    "difficulty": "medium",
}


class TestValidateMCQ:

    def test_valid_mcq_passes(self):
        raw = json.dumps(VALID_MCQ)
        result = validate_mcq_response(raw, KNOWN_IDS)
        assert result["abstained"] is False
        assert result["correct_option_id"] == "A"
        assert len(result["options"]) == 4

    def test_abstention_is_valid(self):
        raw = json.dumps({"abstained": True, "reason": "Not enough evidence"})
        result = validate_mcq_response(raw, KNOWN_IDS)
        assert result["abstained"] is True

    def test_abstention_without_reason_fails(self):
        raw = json.dumps({"abstained": True})
        with pytest.raises(ValidationError, match="reason"):
            validate_mcq_response(raw, KNOWN_IDS)

    def test_missing_question_text_fails(self):
        data = {**VALID_MCQ, "question_text": ""}
        with pytest.raises(ValidationError, match="question_text"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_three_options_fails(self):
        data = {**VALID_MCQ, "options": VALID_MCQ["options"][:3]}
        with pytest.raises(ValidationError, match="4"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_duplicate_option_ids_fails(self):
        opts = [
            {"option_id": "A", "text": "X"},
            {"option_id": "A", "text": "Y"},
            {"option_id": "C", "text": "Z"},
            {"option_id": "D", "text": "W"},
        ]
        data = {**VALID_MCQ, "options": opts}
        with pytest.raises(ValidationError, match="unique"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_duplicate_option_texts_fails(self):
        opts = [
            {"option_id": "A", "text": "same"},
            {"option_id": "B", "text": "SAME"},
            {"option_id": "C", "text": "Z"},
            {"option_id": "D", "text": "W"},
        ]
        data = {**VALID_MCQ, "options": opts}
        with pytest.raises(ValidationError, match="duplicate"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_unknown_passage_id_fails(self):
        data = {**VALID_MCQ, "source_passage_ids": ["pas_999"]}
        with pytest.raises(ValidationError, match="unknown"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_invalid_correct_option_fails(self):
        data = {**VALID_MCQ, "correct_option_id": "E"}
        with pytest.raises(ValidationError, match="correct_option_id"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)

    def test_markdown_fences_stripped(self):
        raw = "```json\n" + json.dumps(VALID_MCQ) + "\n```"
        result = validate_mcq_response(raw, KNOWN_IDS)
        assert result["abstained"] is False

    def test_invalid_json_fails(self):
        with pytest.raises(ValidationError, match="not valid JSON"):
            validate_mcq_response("this is not json", KNOWN_IDS)

    def test_empty_source_ids_fails(self):
        data = {**VALID_MCQ, "source_passage_ids": []}
        with pytest.raises(ValidationError, match="non-empty"):
            validate_mcq_response(json.dumps(data), KNOWN_IDS)


class TestValidateQA:

    def test_valid_qa_passes(self):
        raw = json.dumps({
            "abstained": False,
            "answer": "Photosynthesis converts light to chemical energy.",
            "source_passage_ids": ["pas_001"],
            "confidence_note": "Stated directly in passage.",
        })
        result = validate_qa_response(raw, KNOWN_IDS)
        assert result["abstained"] is False
        assert "Photosynthesis" in result["answer"]

    def test_qa_abstention(self):
        raw = json.dumps({
            "abstained": True,
            "reason": "The selected textbook content did not provide sufficient evidence.",
        })
        result = validate_qa_response(raw, KNOWN_IDS)
        assert result["abstained"] is True

    def test_qa_empty_answer_fails(self):
        raw = json.dumps({
            "abstained": False,
            "answer": "",
            "source_passage_ids": ["pas_001"],
        })
        with pytest.raises(ValidationError, match="answer"):
            validate_qa_response(raw, KNOWN_IDS)
