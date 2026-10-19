"""
backend/rag/retriever.py
FAISS-backed retriever with metadata filters.
The retrieval interface is kept abstract so it can be swapped later.
"""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Protocol, runtime_checkable

import numpy as np

logger = logging.getLogger(__name__)


@runtime_checkable
class Retriever(Protocol):
    def retrieve(
        self,
        query: str,
        subject_id: str | None = None,
        chapter_id: str | None = None,
        source_id: str | None = None,
        top_k: int = 6,
    ) -> list[dict]: ...


class FAISSRetriever:
    """
    FAISS-backed retriever.
    Index and metadata are stored in <index_path>/<index_version>/.
    """

    def __init__(self, index_version: str = "v1") -> None:
        from ..config import get_config

        self._cfg = get_config()
        self._index_version = index_version
        self._index_dir = Path(self._cfg.faiss_index_path) / index_version
        self._faiss_index = None
        self._metadata: list[dict] = []

    def _ensure_loaded(self) -> None:
        index_file = self._index_dir / "passages.faiss"
        meta_file = self._index_dir / "passages_metadata.json"

        if not index_file.exists() or not meta_file.exists():
            raise FileNotFoundError(
                f"FAISS index not found at {self._index_dir}. "
                "Run the ingestion pipeline first."
            )

        current_mtime = index_file.stat().st_mtime
        if self._faiss_index is not None and getattr(self, "_loaded_mtime", 0) == current_mtime:
            return

        try:
            import faiss  # type: ignore
        except ImportError as exc:
            raise ImportError("faiss-cpu is required. pip install faiss-cpu") from exc

        logger.info("Loading FAISS index from %s", self._index_dir)
        self._faiss_index = faiss.read_index(str(index_file))
        with open(meta_file, encoding="utf-8") as f:
            self._metadata = json.load(f)
        self._loaded_mtime = current_mtime

    def retrieve(
        self,
        query: str,
        subject_id: str | None = None,
        chapter_id: str | None = None,
        source_id: str | None = None,
        top_k: int = 6,
    ) -> list[dict]:
        """
        Retrieve the top-k relevant passages, applying optional metadata filters.
        """
        if not query or not query.strip():
            raise ValueError("query must not be empty")
        if top_k < 1 or top_k > 50:
            raise ValueError("top_k must be between 1 and 50")

        self._ensure_loaded()

        from .embeddings import embed_query

        q_vec = embed_query(query).reshape(1, -1)
        # Retrieve more than top_k to account for post-filter reduction
        search_k = min(top_k * 5, len(self._metadata))
        distances, indices = self._faiss_index.search(q_vec, search_k)

        results: list[dict] = []
        for dist, idx in zip(distances[0], indices[0]):
            if idx < 0 or idx >= len(self._metadata):
                continue
            meta = self._metadata[idx]
            if subject_id and meta.get("subject_id") != subject_id:
                continue
            if chapter_id and meta.get("chapter_id") != chapter_id:
                continue
            if source_id and meta.get("source_id") != source_id:
                continue
            results.append({**meta, "_score": float(dist)})
            if len(results) >= top_k:
                break

        return results

    def save_index(
        self,
        embeddings: np.ndarray,
        metadata: list[dict],
        append: bool = False,
    ) -> None:
        """Persist a FAISS index + metadata JSON to disk.
        If append is True and existing index files exist, append new vectors and metadata."""
        try:
            import faiss  # type: ignore
        except ImportError as exc:
            raise ImportError("faiss-cpu is required. pip install faiss-cpu") from exc

        self._index_dir.mkdir(parents=True, exist_ok=True)
        index_file = self._index_dir / "passages.faiss"
        meta_file = self._index_dir / "passages_metadata.json"

        if append and index_file.exists() and meta_file.exists():
            try:
                index = faiss.read_index(str(index_file))
                with open(meta_file, encoding="utf-8") as f:
                    existing_meta = json.load(f)

                existing_pids = {m["passage_id"] for m in existing_meta}
                new_indices = [i for i, m in enumerate(metadata) if m["passage_id"] not in existing_pids]

                if new_indices:
                    new_embeddings = embeddings[new_indices]
                    new_metadata = [metadata[i] for i in new_indices]
                    index.add(new_embeddings)
                    combined_meta = existing_meta + new_metadata
                else:
                    combined_meta = existing_meta

                faiss.write_index(index, str(index_file))
                with open(meta_file, "w", encoding="utf-8") as f:
                    json.dump(combined_meta, f, ensure_ascii=False, indent=2)

                logger.info(
                    "Appended to FAISS index: added %d new vectors (total %d vectors) in %s",
                    len(new_indices),
                    len(combined_meta),
                    self._index_dir,
                )
                self._faiss_index = index
                self._metadata = combined_meta
                self._loaded_mtime = index_file.stat().st_mtime
                return
            except Exception as exc:
                logger.warning("Failed to append to existing FAISS index (%s), recreating...", exc)

        dim = embeddings.shape[1]
        index = faiss.IndexFlatL2(dim)
        index.add(embeddings)

        faiss.write_index(index, str(index_file))
        with open(meta_file, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)

        self._faiss_index = index
        self._metadata = metadata
        self._loaded_mtime = index_file.stat().st_mtime

        logger.info(
            "Saved FAISS index (%d vectors, dim=%d) to %s",
            embeddings.shape[0],
            dim,
            self._index_dir,
        )


class PgVectorRetriever:
    """Retriever backed by PostgreSQL + pgvector (Supabase)."""

    def retrieve(
        self,
        query: str,
        subject_id: str | None = None,
        chapter_id: str | None = None,
        source_id: str | None = None,
        top_k: int = 6,
    ) -> list[dict]:
        if not query or not query.strip():
            raise ValueError("query must not be empty")
        if top_k < 1 or top_k > 50:
            raise ValueError("top_k must be between 1 and 50")

        from .embeddings import embed_query
        from ..repositories.db import get_db

        q_vec = embed_query(query).tolist()
        q_vec_str = "[" + ",".join(f"{x:.6f}" for x in q_vec) + "]"

        where_clauses = []
        params = []

        if subject_id:
            where_clauses.append("subject_id = %s")
            params.append(subject_id)
        if chapter_id:
            where_clauses.append("chapter_id = %s")
            params.append(chapter_id)
        if source_id:
            where_clauses.append("source_id = %s")
            params.append(source_id)

        where_sql = f"WHERE {' AND '.join(where_clauses)}" if where_clauses else ""
        sql = f"""
            SELECT passage_id, source_id, subject_id, chapter_id, chapter_title,
                   language, pdf_page_index, printed_page_label, section_heading, text,
                   content_hash, extraction_method, extraction_quality,
                   1 - (embedding <=> %s::vector) AS similarity
            FROM passages
            {where_sql}
            ORDER BY embedding <=> %s::vector
            LIMIT %s
        """
        all_params = [q_vec_str] + params + [q_vec_str, top_k]

        with get_db() as conn:
            cur = conn.cursor()
            cur.execute(sql, all_params)
            rows = cur.fetchall()

        return [dict(r) for r in rows]


def get_default_retriever() -> Retriever:
    """Return appropriate retriever based on config (PgVector for Supabase, FAISS for SQLite)."""
    from ..config import get_config
    cfg = get_config()
    if cfg.is_postgres:
        return PgVectorRetriever()
    return FAISSRetriever()
