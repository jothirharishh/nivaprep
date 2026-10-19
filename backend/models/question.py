"""
backend/models/question.py
Question data model with strict validation rules.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Optional


class QuestionOrigin(str, Enum):
    TEXTBOOK = "textbook"
    ADAPTED = "adapted"
    AI_GENERATED = "ai_generated"


class QuestionType(str, Enum):
    MCQ = "mcq"
    TRUE_FALSE = "true_false"
    FILL_BLANK = "fill_blank"
    SHORT_ONE_MARK = "short_one_mark"


class Difficulty(str, Enum):
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"
    UNKNOWN = "unknown"


class ReviewStatus(str, Enum):
    DRAFT = "draft"
    PENDING_REVIEW = "pending_review"
    VERIFIED = "verified"
    REJECTED = "rejected"
    RETIRED = "retired"


@dataclass
class QuestionOption:
    option_id: str   # "A", "B", "C", "D"
    text: str

    def to_dict(self) -> dict:
        return {"option_id": self.option_id, "text": self.text}

    @classmethod
    def from_dict(cls, data: dict) -> "QuestionOption":
        return cls(option_id=data["option_id"], text=data["text"])


@dataclass
class SourceRef:
    passage_id: str
    pdf_page_index: int
    printed_page_label: str

    def to_dict(self) -> dict:
        return {
            "passage_id": self.passage_id,
            "pdf_page_index": self.pdf_page_index,
            "printed_page_label": self.printed_page_label,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "SourceRef":
        return cls(
            passage_id=data["passage_id"],
            pdf_page_index=int(data.get("pdf_page_index", 0)),
            printed_page_label=str(data.get("printed_page_label", "")),
        )


@dataclass
class Question:
    question_id: str
    subject_id: str
    source_id: str
    chapter_id: str
    chapter_title: str
    origin: QuestionOrigin
    question_text: str
    options: list[QuestionOption]
    correct_option_id: str
    language: str = "en"
    question_type: QuestionType = QuestionType.MCQ
    explanation: str = ""
    source_refs: list[SourceRef] = field(default_factory=list)
    difficulty: Difficulty = Difficulty.UNKNOWN
    review_status: ReviewStatus = ReviewStatus.DRAFT
    content_version: int = 1
    created_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    review_notes: Optional[str] = None
    reviewed_by: Optional[str] = None
    reviewed_at: Optional[datetime] = None
    model_provider: Optional[str] = None
    model_id: Optional[str] = None
    prompt_version: Optional[str] = None

    # ── Validation ────────────────────────────────────────────────────────────

    def validate(self) -> list[str]:
        errors: list[str] = []
        errors.extend(self._validate_identity())
        if self.question_type == QuestionType.MCQ:
            errors.extend(self._validate_mcq())
        errors.extend(self._validate_verified_constraints())
        return errors

    def _validate_identity(self) -> list[str]:
        errors: list[str] = []
        if not self.question_id:
            errors.append("question_id must not be empty")
        if not self.question_text or not self.question_text.strip():
            errors.append("question_text must not be empty")
        if not self.explanation or not self.explanation.strip():
            errors.append("explanation must not be empty")
        return errors

    def _validate_mcq(self) -> list[str]:
        errors: list[str] = []
        if len(self.options) != 4:
            errors.append(
                f"MCQ requires exactly 4 options; got {len(self.options)}"
            )
        option_ids = [o.option_id for o in self.options]
        if len(set(option_ids)) != len(option_ids):
            errors.append("option IDs must be unique")
        option_texts_normalized = [o.text.strip().lower() for o in self.options]
        if len(set(option_texts_normalized)) != len(option_texts_normalized):
            errors.append("option texts must not be duplicates (after normalisation)")
        if self.correct_option_id not in option_ids:
            errors.append(
                f"correct_option_id '{self.correct_option_id}' not found in option IDs"
            )
        for opt in self.options:
            if not opt.option_id:
                errors.append("each option must have a non-empty option_id")
            if not opt.text or not opt.text.strip():
                errors.append(f"option '{opt.option_id}' text must not be empty")
        return errors

    def _validate_verified_constraints(self) -> list[str]:
        """Extra rules that apply when a question is being marked verified."""
        errors: list[str] = []
        if self.review_status == ReviewStatus.VERIFIED:
            if not self.source_refs:
                errors.append("verified question must have at least one source_ref")
            if not self.source_id:
                errors.append("verified question must have a source_id")
            if not self.reviewed_by:
                errors.append("verified question must have reviewed_by set")
            if self.reviewed_at is None:
                errors.append("verified question must have reviewed_at set")
        return errors

    # ── Serialisation ─────────────────────────────────────────────────────────

    def to_dict(self) -> dict:
        return {
            "question_id": self.question_id,
            "subject_id": self.subject_id,
            "source_id": self.source_id,
            "chapter_id": self.chapter_id,
            "chapter_title": self.chapter_title,
            "language": self.language,
            "origin": self.origin.value,
            "question_type": self.question_type.value,
            "question_text": self.question_text,
            "options": [o.to_dict() for o in self.options],
            "correct_option_id": self.correct_option_id,
            "explanation": self.explanation,
            "source_refs": [r.to_dict() for r in self.source_refs],
            "difficulty": self.difficulty.value,
            "review_status": self.review_status.value,
            "review_notes": self.review_notes,
            "reviewed_by": self.reviewed_by,
            "reviewed_at": self.reviewed_at.isoformat() if self.reviewed_at else None,
            "model_provider": self.model_provider,
            "model_id": self.model_id,
            "prompt_version": self.prompt_version,
            "content_version": self.content_version,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Question":
        return cls(
            question_id=data["question_id"],
            subject_id=data["subject_id"],
            source_id=data.get("source_id", ""),
            chapter_id=data["chapter_id"],
            chapter_title=data.get("chapter_title", ""),
            language=data.get("language", "en"),
            origin=QuestionOrigin(data["origin"]),
            question_type=QuestionType(data.get("question_type", QuestionType.MCQ.value)),
            question_text=data["question_text"],
            options=[QuestionOption.from_dict(o) for o in data.get("options", [])],
            correct_option_id=data["correct_option_id"],
            explanation=data.get("explanation", ""),
            source_refs=[SourceRef.from_dict(r) for r in data.get("source_refs", [])],
            difficulty=Difficulty(data.get("difficulty", Difficulty.UNKNOWN.value)),
            review_status=ReviewStatus(data.get("review_status", ReviewStatus.DRAFT.value)),
            review_notes=data.get("review_notes"),
            reviewed_by=data.get("reviewed_by"),
            reviewed_at=datetime.fromisoformat(data["reviewed_at"])
            if data.get("reviewed_at")
            else None,
            model_provider=data.get("model_provider"),
            model_id=data.get("model_id"),
            prompt_version=data.get("prompt_version"),
            content_version=int(data.get("content_version", 1)),
            created_at=datetime.fromisoformat(data["created_at"])
            if "created_at" in data
            else datetime.now(timezone.utc),
            updated_at=datetime.fromisoformat(data["updated_at"])
            if "updated_at" in data
            else datetime.now(timezone.utc),
        )
