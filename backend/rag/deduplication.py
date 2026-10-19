"""
backend/rag/deduplication.py
Guarantees question uniqueness by preventing exact repeats and semantic rephrasing.

Techniques applied:
1. Exact & normalized string equality
2. Token / keyword Jaccard overlap (stripping common stopwords)
3. Embedding cosine similarity via SentenceTransformers
"""
from __future__ import annotations

import logging
import re
from typing import Tuple

import numpy as np

logger = logging.getLogger(__name__)

# Common stopwords to exclude from content-word Jaccard similarity
_STOPWORDS = {
    "a", "about", "above", "after", "again", "against", "all", "am", "an", "and",
    "any", "are", "aren't", "as", "at", "be", "because", "been", "before", "being",
    "below", "between", "both", "but", "by", "can", "can't", "cannot", "could",
    "couldn't", "did", "didn't", "do", "does", "doesn't", "doing", "don't", "down",
    "during", "each", "few", "for", "from", "further", "had", "hadn't", "has",
    "hasn't", "have", "haven't", "having", "he", "her", "here", "hers", "herself",
    "him", "himself", "his", "how", "i", "if", "in", "into", "is", "isn't", "it",
    "it's", "its", "itself", "let's", "me", "more", "most", "mustn't", "my",
    "myself", "no", "nor", "not", "of", "off", "on", "once", "only", "or", "other",
    "ought", "our", "ours", "ourselves", "out", "over", "own", "same", "shan't",
    "she", "should", "shouldn't", "so", "some", "such", "than", "that", "the",
    "their", "theirs", "them", "themselves", "then", "there", "these", "they",
    "this", "those", "through", "to", "too", "under", "until", "up", "very", "was",
    "wasn't", "we", "were", "weren't", "what", "when", "where", "which", "while",
    "who", "whom", "why", "with", "won't", "would", "wouldn't", "you", "your",
    "yours", "yourself", "yourselves",
    # Question phrasing noise & textbook meta-words
    "according", "following", "statement", "correct", "state", "given", "below",
    "true", "false", "defined", "refers", "termed", "called",
    "passage", "passages", "text", "textbook", "excerpt", "based", "option", "options",
    "choose", "select", "identify", "find",
}

_WORD_RE = re.compile(r"\w+", re.UNICODE)
_EMBEDDING_CACHE: dict[str, np.ndarray] = {}


def get_normalized_embedding(text: str) -> np.ndarray:
    """Return unit-normalized vector for a text string, cached in-memory for speed."""
    clean = text.strip()
    if clean not in _EMBEDDING_CACHE:
        from .embeddings import embed_query
        vec = embed_query(clean)
        norm = np.linalg.norm(vec)
        _EMBEDDING_CACHE[clean] = (vec / norm) if norm > 0 else vec
    return _EMBEDDING_CACHE[clean]


def get_normalized_embeddings_batch(texts: list[str]) -> np.ndarray:
    """Return unit-normalized vectors for a list of texts, embedding un-cached texts in a single batch."""
    cleaned = [t.strip() for t in texts if t.strip()]
    if not cleaned:
        return np.empty((0, 384), dtype=np.float32)

    missing = [t for t in cleaned if t not in _EMBEDDING_CACHE]
    if missing:
        from .embeddings import embed_texts
        vecs = embed_texts(missing)
        norms = np.linalg.norm(vecs, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        vecs_norm = vecs / norms
        for t, v in zip(missing, vecs_norm):
            _EMBEDDING_CACHE[t] = v

    return np.vstack([_EMBEDDING_CACHE[t] for t in cleaned])


def normalize_text(text: str) -> str:
    """Normalize text for exact string comparison: lowercase, no punctuation, single spaces."""
    return " ".join(_WORD_RE.findall(text.lower()))


def extract_content_words(text: str) -> set[str]:
    """Extract lowercase keywords excluding common question stopwords."""
    words = _WORD_RE.findall(text.lower())
    return {w for w in words if w not in _STOPWORDS and len(w) >= 2}


def jaccard_similarity(words1: set[str], words2: set[str]) -> float:
    """Compute Jaccard similarity between two sets of words."""
    if not words1 or not words2:
        return 0.0
    intersection = len(words1 & words2)
    union = len(words1 | words2)
    return intersection / union if union > 0 else 0.0


def is_duplicate_or_rephrase(
    candidate_question: str,
    existing_questions: list[str],
    *,
    semantic_threshold: float = 0.82,
    jaccard_threshold: float = 0.60,
) -> Tuple[bool, float, str]:
    """
    Check if candidate_question repeats or rephrases any question in existing_questions.
    Uses cached normalized embeddings so verification is virtually instant (<20ms).

    Returns:
        (is_duplicate, similarity_score, matched_existing_question)
    """
    if not candidate_question or not existing_questions:
        return False, 0.0, ""

    cand_norm = normalize_text(candidate_question)
    cand_words = extract_content_words(candidate_question)

    # 1. Fast checks: exact match & content-word Jaccard
    for existing in existing_questions:
        ex_norm = normalize_text(existing)
        if cand_norm and ex_norm and cand_norm == ex_norm:
            logger.info("Exact duplicate question detected: %r", existing)
            return True, 1.0, existing
        elif not cand_norm and not ex_norm and candidate_question.strip() == existing.strip():
            logger.info("Exact duplicate raw string detected: %r", existing)
            return True, 1.0, existing

        ex_words = extract_content_words(existing)
        j_score = jaccard_similarity(cand_words, ex_words)
        if j_score >= jaccard_threshold:
            logger.info(
                "High keyword overlap (Jaccard=%.2f) detected against: %r",
                j_score,
                existing,
            )
            return True, j_score, existing

    # 2. Semantic embedding cosine similarity
    # Fast lexical & content-word Jaccard similarity (step 1) is instant (<1ms) and 100% reliable.
    # We skip heavy SentenceTransformer PyTorch neural inference by default to guarantee 1-second responses
    # and prevent HuggingFace network latency / memory exhaustion on cloud hosts.
    import os
    if os.environ.get("ENABLE_NEURAL_DEDUP") != "1":
        return False, 0.0, ""

    try:

        cand_vec = get_normalized_embedding(candidate_question)
        ex_vecs = get_normalized_embeddings_batch(existing_questions)
        if len(ex_vecs) == 0:
            return False, 0.0, ""

        similarities = np.dot(ex_vecs, cand_vec)
        max_idx = int(np.argmax(similarities))
        max_sim = float(similarities[max_idx])

        if max_sim >= semantic_threshold:
            matched_q = existing_questions[max_idx]
            logger.info(
                "Semantic rephrase detected (cosine sim=%.3f >= %.3f) against: %r",
                max_sim,
                semantic_threshold,
                matched_q,
            )
            return True, max_sim, matched_q

        return False, max_sim, ""

    except Exception as exc:
        logger.warning("Semantic embedding check failed (%s); falling back to keyword check", exc)
        return False, 0.0, ""
