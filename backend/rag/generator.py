"""
backend/rag/generator.py
Groq provider adapter — all LLM calls go through here.
Keeps credentials out of every other module.
"""
from __future__ import annotations

import logging
import time
from typing import Any

import httpx

from ..config import get_config
from .prompts import (
    MCQ_PROMPT_VERSION,
    QA_PROMPT_VERSION,
    MCQ_SYSTEM_PROMPT,
    QA_SYSTEM_PROMPT,
    build_mcq_user_prompt,
    build_qa_user_prompt,
)
from .validation import ValidationError, validate_mcq_response, validate_qa_response

logger = logging.getLogger(__name__)

GROQ_CHAT_URL = "https://api.groq.com/openai/v1/chat/completions"

# HTTP status codes that are safe to retry
_RETRYABLE_STATUS = {429, 500, 502, 503, 504}

_client: httpx.Client | None = None


def _get_http_client() -> httpx.Client:
    global _client
    if _client is None or _client.is_closed:
        cfg = get_config()
        _client = httpx.Client(
            timeout=cfg.groq_timeout_seconds,
            limits=httpx.Limits(max_keepalive_connections=10, max_connections=20),
        )
    return _client


class GroqError(Exception):
    """Raised when the Groq API returns a non-retryable error."""


class GroqRateLimitError(GroqError):
    """Raised after exhausting retries on 429 responses."""


def _call_groq(
    messages: list[dict],
    *,
    max_tokens: int = 750,
    temperature: float = 0.3,
    json_mode: bool = True,
) -> str:
    """
    Make a single chat-completion request to Groq using a pooled HTTP connection.
    Raises GroqError on permanent failure, GroqRateLimitError after retries.
    Returns the raw content string.
    """
    cfg = get_config()
    if not cfg.groq_api_key or cfg.groq_api_key.startswith("your_"):
        raise GroqError("GROQ_API_KEY is not configured. Set a valid Groq API key in your .env file.")

    headers = {
        "Authorization": f"Bearer {cfg.groq_api_key}",
        "Content-Type": "application/json",
    }
    payload: dict[str, Any] = {
        "model": cfg.groq_model,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
    }
    if "oss" in cfg.groq_model.lower():
        payload["reasoning_effort"] = "low"

    client = _get_http_client()
    last_exc: Exception | None = None
    for attempt in range(1, cfg.groq_max_retries + 1):
        try:
            resp = client.post(
                GROQ_CHAT_URL,
                headers=headers,
                json=payload,
            )
        except httpx.TimeoutException as exc:
            logger.warning("Groq request timed out (attempt %d/%d)", attempt, cfg.groq_max_retries)
            last_exc = exc
            _wait_before_retry(attempt)
            continue
        except httpx.RequestError as exc:
            logger.warning("Groq network error (attempt %d/%d): %s", attempt, cfg.groq_max_retries, exc)
            last_exc = exc
            _wait_before_retry(attempt)
            continue

        if resp.status_code == 200:
            try:
                body = resp.json()
                return body["choices"][0]["message"]["content"]
            except (KeyError, IndexError, ValueError) as exc:
                raise GroqError(f"Unexpected Groq response shape: {exc}") from exc

        if resp.status_code not in _RETRYABLE_STATUS:
            # Self-healing: if model is not available on this Groq account, discover and auto-switch
            if resp.status_code == 404 and "model_not_found" in resp.text:
                logger.warning(
                    "Configured model %s not available on this Groq account. Discovering supported models...",
                    cfg.groq_model,
                )
                try:
                    models_resp = client.get("https://api.groq.com/openai/v1/models", headers=headers)
                    if models_resp.status_code == 200:
                        avail = [m["id"] for m in models_resp.json().get("data", [])]
                        for pref in ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b", "llama-3.3-70b-versatile"]:
                            if pref in avail:
                                logger.info("Auto-switching to available model: %s", pref)
                                payload["model"] = pref
                                if "oss" in pref.lower():
                                    payload["reasoning_effort"] = "low"
                                else:
                                    payload.pop("reasoning_effort", None)
                                retry_resp = client.post(GROQ_CHAT_URL, headers=headers, json=payload)
                                if retry_resp.status_code == 200:
                                    return retry_resp.json()["choices"][0]["message"]["content"]
                except Exception as auto_err:
                    logger.warning("Auto model discovery failed: %s", auto_err)

            raise GroqError(
                f"Groq returned non-retryable status {resp.status_code}: {resp.text[:200]}"
            )

        logger.warning(
            "Groq returned %d (attempt %d/%d)", resp.status_code, attempt, cfg.groq_max_retries
        )
        last_exc = GroqRateLimitError(f"Status {resp.status_code}")
        _wait_before_retry(attempt, resp)

    raise (last_exc or GroqError("Groq call failed after retries"))


def _wait_before_retry(attempt: int, resp: httpx.Response | None = None) -> None:
    wait = float(min(2 ** attempt, 30))
    if resp is not None:
        retry_after = resp.headers.get("retry-after")
        if retry_after:
            try:
                wait = max(wait, min(float(retry_after), 35.0))
            except ValueError:
                pass
        else:
            reset_tokens = resp.headers.get("x-ratelimit-reset-tokens")
            if reset_tokens:
                try:
                    val = float(reset_tokens.rstrip("s"))
                    wait = max(wait, min(val + 1.0, 35.0))
                except ValueError:
                    pass
    logger.info("Waiting %.1fs before retry", wait)
    time.sleep(wait)


# ── Public API ────────────────────────────────────────────────────────────────

def generate_mcq(
    passages: list[dict],
    subject: str,
    chapter_title: str,
    existing_questions: list[str] | None = None,
) -> dict[str, Any]:
    """
    Generate one candidate MCQ grounded in the provided passages.
    Avoids repeating or rephrasing questions in existing_questions.
    Returns a validated dict or raises ValidationError / GroqError.
    """
    known_ids = {p["passage_id"] for p in passages}
    messages = [
        {"role": "system", "content": MCQ_SYSTEM_PROMPT},
        {
            "role": "user",
            "content": build_mcq_user_prompt(
                passages, subject, chapter_title, existing_questions
            ),
        },
    ]
    raw = _call_groq(messages, max_tokens=750, temperature=0.3, json_mode=True)
    result = validate_mcq_response(raw, known_ids)
    result["prompt_version"] = MCQ_PROMPT_VERSION
    result["model_id"] = get_config().groq_model
    return result


def answer_question(
    question: str,
    passages: list[dict],
    subject: str,
    chapter_title: str,
) -> dict[str, Any]:
    """
    Answer a student question grounded in the provided passages.
    Returns a validated dict or raises ValidationError / GroqError.
    """
    if len(question) > 1000:
        raise ValueError("Question text exceeds maximum allowed length")
    known_ids = {p["passage_id"] for p in passages}
    messages = [
        {"role": "system", "content": QA_SYSTEM_PROMPT},
        {"role": "user", "content": build_qa_user_prompt(question, passages, subject, chapter_title)},
    ]
    raw = _call_groq(messages)
    result = validate_qa_response(raw, known_ids)
    result["prompt_version"] = QA_PROMPT_VERSION
    result["model_id"] = get_config().groq_model
    return result
