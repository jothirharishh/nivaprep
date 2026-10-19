"""
backend/api/textbook_qa.py
Grounded textbook Q&A endpoint.
"""
from __future__ import annotations

import logging
from flask import Blueprint, jsonify, request

from ..rag.retriever import Retriever, get_default_retriever
from ..rag.generator import answer_question, GroqError
from ..rag.validation import ValidationError
from ..repositories import SUBJECT_IDS

logger = logging.getLogger(__name__)
bp = Blueprint("textbook_qa", __name__, url_prefix="/v1/textbook")

_retriever: Retriever | None = None


def _get_retriever() -> Retriever:
    global _retriever
    if _retriever is None:
        _retriever = get_default_retriever()
    return _retriever


@bp.post("/ask")
def ask():
    """
    POST /v1/textbook/ask
    Body: {"question": "...", "subject_id": "...", "chapter_id": "...", "source_id": "..."}
    """
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"error": "Request body must be JSON"}), 400

    question_text = str(body.get("question", "")).strip()
    subject_id = body.get("subject_id")
    chapter_id = body.get("chapter_id")
    source_id = body.get("source_id")

    if not question_text:
        return jsonify({"error": "question must not be empty"}), 400
    if len(question_text) > 1000:
        return jsonify({"error": "question text too long (max 1000 chars)"}), 400
    if subject_id and subject_id not in SUBJECT_IDS:
        return jsonify({"error": f"Unknown subject_id: {subject_id!r}"}), 400

    from ..config import get_config
    top_k = get_config().max_retrieval_chunks

    try:
        retriever = _get_retriever()
        passages = retriever.retrieve(
            query=question_text,
            subject_id=subject_id,
            chapter_id=chapter_id,
            source_id=source_id,
            top_k=top_k,
        )
    except (FileNotFoundError, ImportError) as exc:
        return jsonify({"error": "No textbook index available yet.", "detail": str(exc)}), 503
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    if not passages:
        return jsonify({
            "abstained": True,
            "answer": None,
            "reason": "No relevant passages found in the selected textbook content.",
            "source_refs": [],
        })

    # Infer subject/chapter from retrieved passages if not supplied
    chapter_title = passages[0].get("chapter_title", "") if passages else ""

    try:
        result = answer_question(
            question=question_text,
            passages=passages,
            subject=subject_id or passages[0].get("subject_id", ""),
            chapter_title=chapter_title,
        )
    except ValidationError as exc:
        logger.warning("Q&A validation error: %s", exc)
        return jsonify({"error": "LLM response validation failed", "detail": str(exc)}), 502
    except GroqError as exc:
        logger.error("Groq error: %s", exc)
        return jsonify({"error": "LLM service unavailable", "detail": str(exc)}), 503

    source_refs = [
        {
            "passage_id": p["passage_id"],
            "chapter_title": p.get("chapter_title", ""),
            "pdf_page_index": p.get("pdf_page_index"),
            "printed_page_label": p.get("printed_page_label", ""),
        }
        for p in passages
        if p["passage_id"] in result.get("source_passage_ids", [])
    ]

    return jsonify({
        "abstained": result.get("abstained", False),
        "answer": result.get("answer"),
        "reason": result.get("reason"),
        "source_refs": source_refs,
        "model_id": result.get("model_id"),
        "prompt_version": result.get("prompt_version"),
    })
