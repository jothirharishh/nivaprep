"""
backend/api/admin_generation.py
Admin-only generation job endpoint.
Protected by X-Admin-Key header.
"""
from __future__ import annotations

import functools
import json
import logging
import uuid
from datetime import datetime, timezone

from flask import Blueprint, jsonify, request

from ..repositories import QuestionRepository, SUBJECT_IDS
from ..repositories.db import get_db
from ..rag.retriever import FAISSRetriever
from ..rag.generator import generate_mcq, GroqError
from ..rag.validation import ValidationError
from ..models.question import (
    Difficulty,
    Question,
    QuestionOption,
    QuestionOrigin,
    QuestionType,
    ReviewStatus,
    SourceRef,
)

logger = logging.getLogger(__name__)
bp = Blueprint("admin_generation", __name__, url_prefix="/v1/admin")

_question_repo = QuestionRepository()
_retriever: FAISSRetriever | None = None


def _get_retriever() -> FAISSRetriever:
    global _retriever
    if _retriever is None:
        _retriever = FAISSRetriever()
    return _retriever


def _require_admin(f):
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        from ..config import get_config
        key = request.headers.get("X-Admin-Key", "")
        if not key or key != get_config().admin_api_key:
            return jsonify({"error": "Unauthorised"}), 401
        return f(*args, **kwargs)
    return wrapper


# ── Generation job CRUD ───────────────────────────────────────────────────────

@bp.post("/generation-jobs")
@_require_admin
def create_generation_job():
    """
    POST /v1/admin/generation-jobs
    Body: {"subject_id":"...", "source_id":"...", "chapter_id":"...", "requested_count": 10}
    """
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"error": "Request body must be JSON"}), 400

    subject_id = str(body.get("subject_id", "")).strip()
    source_id = str(body.get("source_id", "")).strip()
    chapter_id = str(body.get("chapter_id", "")).strip()
    requested_count = body.get("requested_count", 10)

    if subject_id not in SUBJECT_IDS:
        return jsonify({"error": f"Invalid subject_id: {subject_id!r}"}), 400
    if not source_id:
        return jsonify({"error": "source_id is required"}), 400
    if not chapter_id:
        return jsonify({"error": "chapter_id is required"}), 400
    try:
        requested_count = int(requested_count)
        if not (1 <= requested_count <= 50):
            raise ValueError
    except (TypeError, ValueError):
        return jsonify({"error": "requested_count must be an integer between 1 and 50"}), 400

    from ..config import get_config
    cfg = get_config()
    job_id = f"job_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc).isoformat()

    with get_db() as conn:
        conn.execute(
            """INSERT INTO generation_jobs (
                job_id, subject_id, source_id, chapter_id, requested_count,
                status, retrieved_passage_ids, model_provider, model_id,
                prompt_version, candidate_question_ids, validation_summary,
                created_at, completed_at
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (
                job_id, subject_id, source_id, chapter_id, requested_count,
                "pending", "[]", "groq", cfg.groq_model, "mcq-v1", "[]", "{}", now, None,
            ),
        )

    # Run synchronously for prototype (production: use a task queue)
    _run_generation_job(job_id, subject_id, source_id, chapter_id, requested_count, cfg)

    return jsonify({"job_id": job_id, "status": "completed"}), 201


@bp.get("/generation-jobs/<job_id>")
@_require_admin
def get_generation_job(job_id: str):
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM generation_jobs WHERE job_id = ?", (job_id,)
        ).fetchone()
    if not row:
        return jsonify({"error": "Job not found"}), 404
    d = dict(row)
    d["retrieved_passage_ids"] = json.loads(d["retrieved_passage_ids"])
    d["candidate_question_ids"] = json.loads(d["candidate_question_ids"])
    d["validation_summary"] = json.loads(d["validation_summary"])
    return jsonify(d)


# ── Internal job runner ───────────────────────────────────────────────────────

def _run_generation_job(
    job_id: str,
    subject_id: str,
    source_id: str,
    chapter_id: str,
    requested_count: int,
    cfg,
) -> None:
    now = datetime.now(timezone.utc).isoformat()

    def _update_job(status: str, extra: dict | None = None):
        extra = extra or {}
        with get_db() as conn:
            conn.execute(
                """UPDATE generation_jobs SET status=?, completed_at=?,
                   candidate_question_ids=?, validation_summary=?,
                   retrieved_passage_ids=?
                   WHERE job_id=?""",
                (
                    status,
                    now,
                    json.dumps(extra.get("candidate_ids", [])),
                    json.dumps(extra.get("validation_summary", {})),
                    json.dumps(extra.get("passage_ids", [])),
                    job_id,
                ),
            )

    try:
        retriever = _get_retriever()
        # Use a semantically meaningful query (chapter title + subject keywords)
        # instead of the opaque chapter_id string for better FAISS retrieval.
        from ..repositories.source_repository import ChapterRepository as _ChapRepo
        _chap_info = _ChapRepo().get_by_id(chapter_id)
        _ch_title = _chap_info["title"] if _chap_info else chapter_id
        _subj_hint = {
            "science": "Science concepts definitions",
            "mathematics": "Mathematics formulas theorems",
            "english": "English grammar prose poetry",
            "social_science": "Social Science history geography",
            "tamil": "Tamil literature grammar",
        }.get(subject_id, subject_id)
        retrieval_query = f"{_ch_title} {_subj_hint} important facts Class 10"
        passages = retriever.retrieve(
            query=retrieval_query,
            subject_id=subject_id,
            chapter_id=chapter_id,
            source_id=source_id,
            top_k=cfg.max_retrieval_chunks,
        )
    except (FileNotFoundError, ImportError) as exc:
        logger.error("Job %s: retriever index not found: %s", job_id, exc)
        _update_job("failed", {"validation_summary": {"error": str(exc)}})
        return

    passage_ids = [p["passage_id"] for p in passages]
    chapter_title = passages[0].get("chapter_title", "") if passages else ""

    candidate_ids: list[str] = []
    validation_summary: dict = {"accepted": 0, "rejected": 0, "abstained": 0, "errors": []}

    for i in range(requested_count):
        try:
            result = generate_mcq(passages, subject_id, chapter_title)
        except (ValidationError, GroqError) as exc:
            validation_summary["rejected"] += 1
            validation_summary["errors"].append(str(exc))
            continue

        if result.get("abstained"):
            validation_summary["abstained"] += 1
            continue

        q = Question(
            question_id=f"q_{uuid.uuid4().hex[:12]}",
            subject_id=subject_id,
            source_id=source_id,
            chapter_id=chapter_id,
            chapter_title=chapter_title,
            language="en",
            origin=QuestionOrigin.AI_GENERATED,
            question_type=QuestionType.MCQ,
            question_text=result["question_text"],
            options=[QuestionOption.from_dict(o) for o in result["options"]],
            correct_option_id=result["correct_option_id"],
            explanation=result["explanation"],
            source_refs=[
                SourceRef(passage_id=pid, pdf_page_index=0, printed_page_label="")
                for pid in result["source_passage_ids"]
            ],
            difficulty=Difficulty(result.get("difficulty", "unknown")),
            review_status=ReviewStatus.PENDING_REVIEW,
            model_provider="groq",
            model_id=result.get("model_id", cfg.groq_model),
            prompt_version=result.get("prompt_version", "mcq-v1"),
            content_version=1,
        )
        errors = q.validate()
        if errors:
            validation_summary["rejected"] += 1
            validation_summary["errors"].extend(errors)
            continue

        try:
            _question_repo.insert(q)
            candidate_ids.append(q.question_id)
            validation_summary["accepted"] += 1
        except Exception as exc:
            validation_summary["rejected"] += 1
            validation_summary["errors"].append(str(exc))

    _update_job(
        "completed",
        {
            "candidate_ids": candidate_ids,
            "validation_summary": validation_summary,
            "passage_ids": passage_ids,
        },
    )
    logger.info(
        "Job %s completed: %d accepted, %d rejected, %d abstained",
        job_id,
        validation_summary["accepted"],
        validation_summary["rejected"],
        validation_summary["abstained"],
    )
