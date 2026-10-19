"""
backend/rag/embeddings.py
Embedding adapter — wraps sentence-transformers.
Model name is configured via env; the retrieval interface is replaceable.
"""
from __future__ import annotations

import logging
from typing import Protocol, runtime_checkable

import numpy as np

logger = logging.getLogger(__name__)

_model = None


@runtime_checkable
class EmbeddingModel(Protocol):
    def encode(self, texts: list[str]) -> np.ndarray: ...


def _load_model(model_name: str) -> EmbeddingModel:
    """Lazy-load sentence-transformers model."""
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore
    except ImportError as exc:
        raise ImportError(
            "sentence-transformers is required. Install it: pip install sentence-transformers"
        ) from exc
    logger.info("Loading embedding model: %s", model_name)
    return SentenceTransformer(model_name)


def get_embedder(model_name: str | None = None) -> EmbeddingModel:
    global _model
    if _model is None:
        from ..config import get_config
        name = model_name or get_config().embedding_model
        _model = _load_model(name)
    return _model


def embed_texts(texts: list[str], model_name: str | None = None) -> np.ndarray:
    """
    Embed a list of text strings.
    Returns a float32 numpy array of shape (len(texts), embedding_dim).
    """
    if not texts:
        raise ValueError("texts must not be empty")
    model = get_embedder(model_name)
    vecs = model.encode(texts)
    return np.array(vecs, dtype=np.float32)


def embed_query(query: str, model_name: str | None = None) -> np.ndarray:
    """Embed a single query string."""
    return embed_texts([query], model_name)[0]
