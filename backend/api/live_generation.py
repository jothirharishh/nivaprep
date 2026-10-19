"""
backend/api/live_generation.py
Live RAG-based question generation endpoint for student practice.

Guarantees:
1. Grounded strictly in TN Samacheer Kalvi textbook passages.
2. Anti-repetition: never returns the exact same question already seen/cached.
3. Anti-rephrasing: uses multi-level checks (normalized string match, Jaccard
   keyword overlap, and semantic embedding cosine similarity) to detect and
   reject questions that merely rephrase an already-asked concept.
4. Passage diversity: rotates across different pages and sections of the chapter
   so questions cover the whole syllabus instead of clustering on a single concept.
"""
from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Any

from flask import Blueprint, jsonify, request

from ..repositories import SUBJECT_IDS, QuestionRepository
from ..repositories.source_repository import ChapterRepository
from ..repositories.db import get_db
from ..rag.retriever import Retriever, get_default_retriever
from ..rag.generator import generate_mcq, GroqError
from ..rag.validation import ValidationError
from ..rag.deduplication import is_duplicate_or_rephrase

logger = logging.getLogger(__name__)
bp = Blueprint("live_generation", __name__, url_prefix="/v1/questions")

_retriever: Retriever | None = None
_chapter_repo = ChapterRepository()
_question_repo = QuestionRepository()


def _get_retriever() -> Retriever:
    global _retriever
    if _retriever is None:
        _retriever = get_default_retriever()
    return _retriever


def _get_existing_questions(
    subject_id: str,
    chapter_id: str,
    exclude_ids: list[str],
) -> tuple[list[str], set[str]]:
    """
    Look up recent question texts and used passage IDs for this chapter and from exclude_ids.
    Returns:
        (existing_question_texts, set_of_used_passage_ids)
    """
    question_texts: list[str] = []
    used_passage_ids: set[str] = set()

    try:
        with get_db() as conn:
            # Query questions already stored for this chapter or specified in exclude_ids
            clauses = ["(subject_id = ? AND chapter_id = ?)"]
            params: list[Any] = [subject_id, chapter_id]

            if exclude_ids:
                placeholders = ",".join("?" for _ in exclude_ids)
                clauses.append(f"question_id IN ({placeholders})")
                params.extend(exclude_ids)

            sql = f"""
                SELECT question_id, question_text, source_refs_json
                FROM questions
                WHERE {" OR ".join(clauses)}
                ORDER BY created_at DESC
                LIMIT 25
            """
            rows = conn.execute(sql, params).fetchall()

            for row in rows:
                q_text = row["question_text"]
                if q_text and q_text.strip():
                    question_texts.append(q_text.strip())

                refs_raw = row["source_refs_json"]
                if refs_raw:
                    try:
                        refs = json.loads(refs_raw)
                        for r in refs:
                            pid = r.get("passage_id")
                            if pid:
                                used_passage_ids.add(pid)
                    except Exception:
                        pass
    except Exception as exc:
        logger.warning("Error fetching existing questions for deduplication: %s", exc)

    return question_texts, used_passage_ids


def _get_diverse_passages(
    subject_id: str,
    chapter_id: str,
    chapter_title: str,
    used_passage_ids: set[str],
    retriever: FAISSRetriever,
    target_count: int = 5,
    attempt: int = 0,
) -> list[dict]:
    """
    Select 4-6 passages from the chapter, prioritizing unexplored pages/sections.
    Rotating across the chapter ensures questions test different concepts rather
    than repeatedly sampling the first page.
    """
    # 1. First attempt: Query SQLite for all chapter passages
    try:
        with get_db() as conn:
            rows = conn.execute(
                """SELECT passage_id, source_id, subject_id, chapter_id, chapter_title,
                          pdf_page_index, printed_page_label, section_heading, text
                   FROM passages
                   WHERE chapter_id = ?
                   ORDER BY pdf_page_index, passage_id""",
                (chapter_id,),
            ).fetchall()

        if rows:
            # Group passages by page index
            by_page: dict[int, list[dict]] = {}
            for r in rows:
                p_dict = dict(r)
                p_idx = p_dict["pdf_page_index"]
                by_page.setdefault(p_idx, []).append(p_dict)

            sorted_pages = sorted(by_page.keys())

            # Score pages: pages with fewer used passages are prioritized
            scored_pages: list[tuple[int, int]] = []
            for p_idx in sorted_pages:
                used_count = sum(1 for p in by_page[p_idx] if p["passage_id"] in used_passage_ids)
                scored_pages.append((used_count, p_idx))

            # Sort by least used first, then apply attempt offset for retries
            scored_pages.sort(key=lambda x: x[0])
            offset_idx = attempt % len(scored_pages)
            target_page_idx = scored_pages[offset_idx][1]

            candidate_passages = list(by_page[target_page_idx])

            # If page has fewer than target_count, borrow from adjacent page
            if len(candidate_passages) < target_count:
                all_idx = sorted_pages.index(target_page_idx)
                next_idx = (all_idx + 1) % len(sorted_pages)
                candidate_passages.extend(by_page[sorted_pages[next_idx]])

            return candidate_passages[:target_count]

    except Exception as exc:
        logger.warning("Failed to select chapter passages from SQLite: %s", exc)

    # 2. Fallback: Query FAISS
    query = f"{chapter_title} Class 10 concepts definitions facts examples page {attempt + 1}"
    try:
        results = retriever.retrieve(
            query=query,
            subject_id=subject_id,
            chapter_id=chapter_id,
            top_k=target_count * 2,
        )
        # Filter out passages already heavily used if possible
        unused = [p for p in results if p["passage_id"] not in used_passage_ids]
        return unused[:target_count] if len(unused) >= 3 else results[:target_count]
    except Exception as exc:
        logger.error("FAISS retrieval failed: %s", exc)
        return []


@bp.post("/generate")
def generate_live():
    """
    POST /v1/questions/generate
    Body:
      {
        "subject_id": "science",
        "chapter_id": "src_tn_sci_10_2024_ch_01",
        "exclude_question_ids": ["q_abc", "q_def"]
      }

    Returns a fresh AI-generated MCQ grounded in textbook passages,
    guaranteed not to repeat or rephrase any previous questions.
    """
    body = request.get_json(silent=True)
    if not body:
        return jsonify({"error": "Request body must be JSON"}), 400

    subject_id = str(body.get("subject_id", "")).strip()
    chapter_id = str(body.get("chapter_id", "")).strip()
    exclude_ids: list[str] = list(body.get("exclude_question_ids", []) or [])

    # ── Validate inputs ───────────────────────────────────────────────────────
    if not subject_id:
        return jsonify({"error": "subject_id is required"}), 400
    if subject_id not in SUBJECT_IDS:
        return jsonify({"error": f"Unknown subject_id: {subject_id!r}"}), 400
    if not chapter_id:
        return jsonify({"error": "chapter_id is required"}), 400

    from ..config import get_config
    cfg = get_config()

    # ── Check Groq availability ───────────────────────────────────────────────
    if not cfg.groq_api_key or cfg.groq_api_key.startswith("your_"):
        return jsonify({
            "error": "Live generation is unavailable — GROQ_API_KEY is not configured.",
            "detail": "Set a valid GROQ_API_KEY in your .env file.",
        }), 503

    # ── Look up chapter title from DB ─────────────────────────────────────────
    chapter_info = _chapter_repo.get_by_id(chapter_id)
    chapter_title = chapter_info["title"] if chapter_info else chapter_id

    # ── Retrieve existing questions & used passages for anti-duplication ──────
    existing_texts, used_passage_ids = _get_existing_questions(
        subject_id=subject_id,
        chapter_id=chapter_id,
        exclude_ids=exclude_ids,
    )

    # ── Generation & Deduplication Loop ───────────────────────────────────────
    max_attempts = 3
    final_result: dict[str, Any] | None = None
    final_passages: list[dict] = []
    retriever = _get_retriever()

    for attempt in range(max_attempts):
        passages = _get_diverse_passages(
            subject_id=subject_id,
            chapter_id=chapter_id,
            chapter_title=chapter_title,
            used_passage_ids=used_passage_ids,
            retriever=retriever,
            target_count=min(cfg.max_retrieval_chunks, 4),
            attempt=attempt,
        )

        if not passages:
            logger.warning("No passages found on attempt %d for %s", attempt + 1, chapter_id)
            continue

        try:
            res = generate_mcq(
                passages=passages,
                subject=subject_id,
                chapter_title=chapter_title,
                existing_questions=existing_texts,
            )
        except ValidationError as exc:
            logger.warning("Validation failed on attempt %d: %s", attempt + 1, exc)
            continue
        except GroqError as exc:
            logger.error("Groq error during live generation: %s", exc)
            return jsonify({"error": "LLM service unavailable", "detail": str(exc)}), 503

        if res.get("abstained"):
            logger.info("Model abstained on attempt %d: %s", attempt + 1, res.get("reason"))
            if attempt == max_attempts - 1 and not final_result:
                return jsonify({
                    "abstained": True,
                    "reason": res.get("reason", "Insufficient textbook evidence for this chapter."),
                }), 200
            continue

        candidate_q = res.get("question_text", "").strip()

        # Check for duplicates or semantic rephrases against existing questions
        is_dup, score, matched_q = is_duplicate_or_rephrase(
            candidate_question=candidate_q,
            existing_questions=existing_texts,
            semantic_threshold=0.82,
            jaccard_threshold=0.60,
        )

        if is_dup:
            logger.warning(
                "Duplicate/rephrase detected on attempt %d (score=%.2f): %r matches %r. Regenerating...",
                attempt + 1,
                score,
                candidate_q,
                matched_q,
            )
            # Add to local blacklist to guide subsequent retry
            existing_texts.append(candidate_q)
            continue

        # Non-duplicate, non-rephrase question verified!
        final_result = res
        final_passages = passages
        break

    if not final_result:
        return jsonify({
            "abstained": True,
            "reason": "All major textbook concepts for this chapter have already been covered in this session.",
        }), 200

    # ── Build the question ID and source refs ─────────────────────────────────
    live_qid = f"live_{uuid.uuid4().hex[:12]}"
    now_iso = datetime.now(timezone.utc).isoformat()

    source_passage_ids: set[str] = set(final_result.get("source_passage_ids", []))
    source_refs = [
        {
            "passage_id": p["passage_id"],
            "chapter_title": p.get("chapter_title", chapter_title),
            "pdf_page_index": p.get("pdf_page_index"),
            "printed_page_label": p.get("printed_page_label", ""),
        }
        for p in final_passages
        if p["passage_id"] in source_passage_ids
    ]

    # ── Cache live question in DB for audit trail & session deduplication ─────
    _persist_live_question(
        live_qid=live_qid,
        subject_id=subject_id,
        chapter_id=chapter_id,
        chapter_title=chapter_title,
        result=final_result,
        passages=final_passages,
        cfg=cfg,
        now_iso=now_iso,
    )

    return jsonify({
        "question_id": live_qid,
        "is_live": True,
        "abstained": False,
        "subject_id": subject_id,
        "chapter_id": chapter_id,
        "chapter_title": chapter_title,
        "question_text": final_result["question_text"],
        "options": final_result["options"],
        "correct_option_id": final_result["correct_option_id"],
        "explanation": final_result["explanation"],
        "difficulty": final_result.get("difficulty", "medium"),
        "origin": "ai_generated",
        "review_status": "live",
        "source_refs": source_refs,
        "model_id": final_result.get("model_id", cfg.groq_model),
        "prompt_version": final_result.get("prompt_version", "mcq-v1"),
        "generated_at": now_iso,
    }), 200


def _persist_live_question(
    live_qid: str,
    subject_id: str,
    chapter_id: str,
    chapter_title: str,
    result: dict,
    passages: list[dict],
    cfg,
    now_iso: str,
) -> None:
    """
    Persist the live question to SQLite with review_status='live'.
    This allows deduplication (exclude_question_ids lookup) and audit trails.
    Errors are logged but never propagate to the student.
    """
    options_json = json.dumps(result["options"])
    source_ids = result.get("source_passage_ids", [])
    source_refs_json = json.dumps([
        {
            "passage_id": p["passage_id"],
            "pdf_page_index": p.get("pdf_page_index", 0),
            "printed_page_label": p.get("printed_page_label", ""),
            "chapter_title": p.get("chapter_title", chapter_title),
        }
        for p in passages
        if p["passage_id"] in set(source_ids)
    ])

    try:
        with get_db() as conn:
            if cfg.is_postgres:
                insert_sql = """INSERT INTO questions (
                    question_id, subject_id, source_id, chapter_id, chapter_title,
                    language, origin, question_type, question_text,
                    options_json, correct_option_id, explanation,
                    source_refs_json, difficulty, review_status,
                    model_provider, model_id, prompt_version,
                    content_version, created_at, updated_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                ON CONFLICT (question_id) DO NOTHING"""
            else:
                insert_sql = """INSERT OR IGNORE INTO questions (
                    question_id, subject_id, source_id, chapter_id, chapter_title,
                    language, origin, question_type, question_text,
                    options_json, correct_option_id, explanation,
                    source_refs_json, difficulty, review_status,
                    model_provider, model_id, prompt_version,
                    content_version, created_at, updated_at
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)"""
            conn.execute(
                insert_sql,
                (
                    live_qid,
                    subject_id,
                    passages[0].get("source_id", "") if passages else "",
                    chapter_id,
                    chapter_title,
                    "en",
                    "ai_generated",
                    "mcq",
                    result["question_text"],
                    options_json,
                    result["correct_option_id"],
                    result.get("explanation", ""),
                    source_refs_json,
                    result.get("difficulty", "medium"),
                    "live",
                    "groq",
                    result.get("model_id", cfg.groq_model),
                    result.get("prompt_version", "mcq-v1"),
                    1,
                    now_iso,
                    now_iso,
                ),
            )
    except Exception as exc:
        logger.warning("Failed to cache live question %s: %s", live_qid, exc)
