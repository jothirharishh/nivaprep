"""
backend/api/questions.py
Question-bank endpoints — public read, admin write.
"""
from __future__ import annotations

import functools
import logging
from flask import Blueprint, jsonify, request, g

from ..repositories import QuestionRepository, SourceRepository, ChapterRepository, SUBJECT_IDS, SUBJECT_DISPLAY
from ..models.question import ReviewStatus

logger = logging.getLogger(__name__)
bp = Blueprint("questions", __name__, url_prefix="/v1")

_question_repo = QuestionRepository()
_source_repo = SourceRepository()
_chapter_repo = ChapterRepository()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _require_admin(f):
    """Decorator that checks the X-Admin-Key header."""
    @functools.wraps(f)
    def wrapper(*args, **kwargs):
        from ..config import get_config
        key = request.headers.get("X-Admin-Key", "")
        if not key or key != get_config().admin_api_key:
            return jsonify({"error": "Unauthorised"}), 401
        return f(*args, **kwargs)
    return wrapper


def _safe_int(value: str | None, default: int, min_val: int, max_val: int) -> int:
    try:
        v = int(value)
        return max(min_val, min(max_val, v))
    except (TypeError, ValueError):
        return default


# ── Subject / chapter endpoints ───────────────────────────────────────────────

@bp.get("/subjects")
def list_subjects():
    """Return the five supported subject areas."""
    subjects = [
        {"subject_id": sid, "display_name": SUBJECT_DISPLAY[sid]}
        for sid in sorted(SUBJECT_IDS)
    ]
    return jsonify({"subjects": subjects})


@bp.get("/subjects/<subject_id>/chapters")
def list_chapters(subject_id: str):
    if subject_id not in SUBJECT_IDS:
        return jsonify({"error": f"Unknown subject_id: {subject_id!r}"}), 404
    sources = [s for s in _source_repo.list_all() if s.subject_id == subject_id]
    question_counts = _question_repo.count_by_chapter(subject_id)
    chapters: list[dict] = []
    seen: set[str] = set()
    for src in sources:
        for ch in _chapter_repo.list_by_source(src.source_id):
            cid = ch["chapter_id"]
            if cid in seen:
                continue
            seen.add(cid)
            item = dict(ch)
            item["question_count"] = question_counts.get(cid, 0)
            chapters.append(item)
    return jsonify({"subject_id": subject_id, "chapters": chapters})


# ── Question read endpoint ────────────────────────────────────────────────────

@bp.get("/questions")
def list_questions():
    """
    Return verified questions with optional filters.
    Query params: subject_id, chapter_id, origin, limit (max 200).
    """
    subject_id = request.args.get("subject_id")
    chapter_id = request.args.get("chapter_id")
    origin = request.args.get("origin")
    limit = _safe_int(request.args.get("limit"), default=50, min_val=1, max_val=200)

    if subject_id and subject_id not in SUBJECT_IDS:
        return jsonify({"error": f"Invalid subject_id: {subject_id!r}"}), 400

    try:
        questions = _question_repo.list_verified(
            subject_id=subject_id,
            chapter_id=chapter_id,
            origin=origin,
            limit=limit,
        )
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    return jsonify({
        "questions": [q.to_dict() for q in questions],
        "count": len(questions),
    })


@bp.get("/questions/<question_id>")
def get_question(question_id: str):
    q = _question_repo.get_by_id(question_id)
    if q is None:
        return jsonify({"error": "Question not found"}), 404
    if q.review_status != ReviewStatus.VERIFIED:
        return jsonify({"error": "Question not available"}), 404
    return jsonify(q.to_dict())


# ── Admin review endpoint ─────────────────────────────────────────────────────

@bp.post("/admin/questions/<question_id>/review")
@_require_admin
def review_question(question_id: str):
    """
    Approve, reject, or retire a question.
    Body: {"action": "approve"|"reject"|"retire", "reviewer": "name", "notes": "..."}
    """
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"error": "Request body must be JSON"}), 400

    action = str(body.get("action", "")).strip()
    reviewer = str(body.get("reviewer", "")).strip()
    notes = body.get("notes")

    if action not in ("approve", "reject", "retire"):
        return jsonify({"error": "action must be approve, reject, or retire"}), 400
    if not reviewer:
        return jsonify({"error": "reviewer must be provided"}), 400

    status_map = {
        "approve": ReviewStatus.VERIFIED,
        "reject": ReviewStatus.REJECTED,
        "retire": ReviewStatus.RETIRED,
    }
    new_status = status_map[action]

    q = _question_repo.get_by_id(question_id)
    if q is None:
        return jsonify({"error": "Question not found"}), 404

    # Validate before approving
    if action == "approve":
        errors = q._validate_verified_constraints()
        # Temporarily set reviewed_by to pass constraint check
        q.reviewed_by = reviewer
        from datetime import datetime, timezone
        q.reviewed_at = datetime.now(timezone.utc)
        errors = q._validate_verified_constraints()
        if errors:
            return jsonify({"error": "Cannot approve", "validation_errors": errors}), 422

    updated = _question_repo.update_review_status(
        question_id, new_status, reviewer, notes
    )
    if not updated:
        return jsonify({"error": "Question not found or update failed"}), 404

    return jsonify({"question_id": question_id, "new_status": new_status.value})
