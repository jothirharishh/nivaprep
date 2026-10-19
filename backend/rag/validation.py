"""
backend/rag/validation.py
Strict schema validation for LLM-generated question output.
Never trust LLM output as safe or correct — validate everything.
"""
from __future__ import annotations

import json
import re
from typing import Any


class ValidationError(Exception):
    pass


ALLOWED_OPTION_IDS = {"A", "B", "C", "D"}
MAX_QUESTION_LENGTH = 1000
MAX_OPTION_LENGTH = 500
MAX_EXPLANATION_LENGTH = 2000


def validate_mcq_response(
    raw: str,
    known_passage_ids: set[str],
) -> dict[str, Any]:
    """
    Parse and validate an LLM MCQ response.
    Returns the validated dict or raises ValidationError with a descriptive message.
    """
    data = _parse_json(raw)

    # Abstention is valid
    if data.get("abstained") is True:
        reason = str(data.get("reason", ""))
        if not reason:
            raise ValidationError("Abstained response must include a reason")
        return {"abstained": True, "reason": reason}

    errors: list[str] = []

    # Required string fields
    question_text = str(data.get("question_text", "")).strip()
    if not question_text:
        errors.append("question_text is missing or empty")
    elif len(question_text) > MAX_QUESTION_LENGTH:
        errors.append(f"question_text exceeds {MAX_QUESTION_LENGTH} characters")

    # Options
    options = data.get("options")
    if not isinstance(options, list) or len(options) != 4:
        errors.append(f"options must be a list of exactly 4 items; got {type(options)}")
    else:
        option_ids: list[str] = []
        option_texts_norm: list[str] = []
        for opt in options:
            if not isinstance(opt, dict):
                errors.append("each option must be a dict")
                continue
            oid = str(opt.get("option_id", "")).strip()
            otext = str(opt.get("text", "")).strip()
            if oid not in ALLOWED_OPTION_IDS:
                errors.append(f"option_id must be one of A/B/C/D; got {oid!r}")
            if not otext:
                errors.append(f"option {oid!r} text is empty")
            if len(otext) > MAX_OPTION_LENGTH:
                errors.append(f"option {oid!r} text exceeds {MAX_OPTION_LENGTH} characters")
            option_ids.append(oid)
            option_texts_norm.append(otext.lower())
        if len(set(option_ids)) != len(option_ids):
            errors.append("option_ids are not unique")
        if len(set(option_texts_norm)) != len(option_texts_norm):
            errors.append("option texts are duplicates (case-insensitive)")

    # Correct option
    correct_option_id = str(data.get("correct_option_id", "")).strip()
    if correct_option_id not in ALLOWED_OPTION_IDS:
        errors.append(f"correct_option_id must be A/B/C/D; got {correct_option_id!r}")
    elif "options" in data and isinstance(data["options"], list):
        ids = [str(o.get("option_id", "")).strip() for o in data["options"] if isinstance(o, dict)]
        if correct_option_id not in ids:
            errors.append(f"correct_option_id {correct_option_id!r} not found in option list")

    # Explanation
    explanation = str(data.get("explanation", "")).strip()
    if not explanation:
        errors.append("explanation is missing or empty")
    elif len(explanation) > MAX_EXPLANATION_LENGTH:
        errors.append(f"explanation exceeds {MAX_EXPLANATION_LENGTH} characters")

    # Source passage IDs
    source_ids = data.get("source_passage_ids")
    if not isinstance(source_ids, list) or len(source_ids) == 0:
        errors.append("source_passage_ids must be a non-empty list")
    else:
        unknown = [sid for sid in source_ids if str(sid) not in known_passage_ids]
        if unknown:
            errors.append(f"unknown source_passage_ids: {unknown}")

    # Difficulty
    difficulty = str(data.get("difficulty", "unknown")).strip()
    if difficulty not in {"easy", "medium", "hard", "unknown"}:
        errors.append(f"difficulty must be easy/medium/hard/unknown; got {difficulty!r}")

    if errors:
        raise ValidationError(f"MCQ validation failed: {'; '.join(errors)}")

    return {
        "abstained": False,
        "question_text": question_text,
        "options": [
            {"option_id": str(o["option_id"]).strip(), "text": str(o["text"]).strip()}
            for o in data["options"]
        ],
        "correct_option_id": correct_option_id,
        "explanation": explanation,
        "source_passage_ids": [str(sid) for sid in source_ids],
        "difficulty": difficulty,
    }


def validate_qa_response(
    raw: str,
    known_passage_ids: set[str],
) -> dict[str, Any]:
    """
    Parse and validate an LLM Q&A response.
    """
    data = _parse_json(raw)

    if data.get("abstained") is True:
        reason = str(data.get("reason", "")).strip()
        if not reason:
            raise ValidationError("Abstained Q&A response must include a reason")
        return {"abstained": True, "reason": reason, "source_passage_ids": []}

    errors: list[str] = []

    answer = str(data.get("answer", "")).strip()
    if not answer:
        errors.append("answer is missing or empty")

    source_ids = data.get("source_passage_ids")
    if not isinstance(source_ids, list) or len(source_ids) == 0:
        errors.append("source_passage_ids must be a non-empty list")
    else:
        unknown = [sid for sid in source_ids if str(sid) not in known_passage_ids]
        if unknown:
            errors.append(f"unknown source_passage_ids: {unknown}")

    if errors:
        raise ValidationError(f"Q&A validation failed: {'; '.join(errors)}")

    return {
        "abstained": False,
        "answer": answer,
        "source_passage_ids": [str(sid) for sid in (source_ids or [])],
        "confidence_note": str(data.get("confidence_note", "")).strip(),
    }


def _parse_json(raw: str) -> dict:
    """Strip markdown fences and parse JSON. Raises ValidationError on failure."""
    text = raw.strip()
    # Remove ```json ... ``` or ``` ... ``` fences
    text = re.sub(r"^```(?:json)?\s*", "", text, flags=re.IGNORECASE)
    text = re.sub(r"\s*```$", "", text)
    try:
        result = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ValidationError(f"LLM output is not valid JSON: {exc}") from exc
    if not isinstance(result, dict):
        raise ValidationError(f"LLM output must be a JSON object; got {type(result).__name__}")
    return result
