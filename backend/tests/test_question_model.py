"""
backend/tests/test_question_model.py
Unit tests for the Question model — no live API required.
"""
import pytest
from datetime import datetime, timezone

from backend.models.question import (
    Difficulty,
    Question,
    QuestionOption,
    QuestionOrigin,
    QuestionType,
    ReviewStatus,
    SourceRef,
)


def _make_valid_mcq(**overrides) -> Question:
    defaults = dict(
        question_id="q_test_001",
        subject_id="science",
        source_id="src_001",
        chapter_id="science_ch01",
        chapter_title="Chemical Reactions",
        language="en",
        origin=QuestionOrigin.AI_GENERATED,
        question_type=QuestionType.MCQ,
        question_text="What is the chemical formula of water?",
        options=[
            QuestionOption("A", "H2O"),
            QuestionOption("B", "CO2"),
            QuestionOption("C", "NaCl"),
            QuestionOption("D", "HCl"),
        ],
        correct_option_id="A",
        explanation="Water is composed of two hydrogen and one oxygen atom.",
        source_refs=[SourceRef("pas_001", 0, "1")],
        difficulty=Difficulty.EASY,
        review_status=ReviewStatus.PENDING_REVIEW,
        content_version=1,
    )
    defaults.update(overrides)
    return Question(**defaults)


class TestQuestionValidation:

    def test_valid_mcq_has_no_errors(self):
        q = _make_valid_mcq()
        assert q.validate() == []

    def test_empty_question_text_raises(self):
        q = _make_valid_mcq(question_text="   ")
        errors = q.validate()
        assert any("question_text" in e for e in errors)

    def test_wrong_option_count_raises(self):
        q = _make_valid_mcq(options=[
            QuestionOption("A", "H2O"),
            QuestionOption("B", "CO2"),
        ])
        errors = q.validate()
        assert any("4" in e for e in errors)

    def test_duplicate_option_ids_raises(self):
        q = _make_valid_mcq(options=[
            QuestionOption("A", "H2O"),
            QuestionOption("A", "CO2"),
            QuestionOption("C", "NaCl"),
            QuestionOption("D", "HCl"),
        ])
        errors = q.validate()
        assert any("unique" in e for e in errors)

    def test_duplicate_option_texts_raises(self):
        q = _make_valid_mcq(options=[
            QuestionOption("A", "H2O"),
            QuestionOption("B", "h2o"),   # duplicate after lowercase
            QuestionOption("C", "NaCl"),
            QuestionOption("D", "HCl"),
        ])
        errors = q.validate()
        assert any("duplicate" in e for e in errors)

    def test_invalid_correct_option_raises(self):
        q = _make_valid_mcq(correct_option_id="E")
        errors = q.validate()
        assert any("correct_option_id" in e for e in errors)

    def test_verified_requires_source_refs(self):
        q = _make_valid_mcq(
            review_status=ReviewStatus.VERIFIED,
            source_refs=[],
            reviewed_by="teacher",
            reviewed_at=datetime.now(timezone.utc),
        )
        errors = q.validate()
        assert any("source_ref" in e for e in errors)

    def test_verified_requires_reviewer(self):
        q = _make_valid_mcq(
            review_status=ReviewStatus.VERIFIED,
            source_refs=[SourceRef("pas_001", 0, "1")],
            reviewed_by=None,
            reviewed_at=datetime.now(timezone.utc),
        )
        errors = q.validate()
        assert any("reviewed_by" in e for e in errors)


class TestQuestionRoundTrip:

    def test_to_dict_from_dict_roundtrip(self):
        q = _make_valid_mcq()
        d = q.to_dict()
        q2 = Question.from_dict(d)
        assert q2.question_id == q.question_id
        assert q2.correct_option_id == q.correct_option_id
        assert len(q2.options) == 4
        assert q2.origin == QuestionOrigin.AI_GENERATED

    def test_from_dict_rejects_unknown_origin(self):
        q = _make_valid_mcq()
        d = q.to_dict()
        d["origin"] = "invented"
        with pytest.raises(ValueError):
            Question.from_dict(d)
