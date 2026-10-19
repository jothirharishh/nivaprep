"""
backend/ingestion/index.py
Build and save FAISS index from a list of chunks.
"""
from __future__ import annotations

import logging
from pathlib import Path

from .chunk import Chunk
from ..rag.embeddings import embed_texts
from ..rag.retriever import FAISSRetriever

logger = logging.getLogger(__name__)


def build_index(
    chunks: list[Chunk],
    index_version: str = "v1",
    append: bool = True,
) -> None:
    """
    Embed all chunks and persist a FAISS index + metadata.
    If append is True, existing indexed chunks from other chapters are preserved.
    """
    if not chunks:
        raise ValueError("Cannot build index from empty chunk list")

    texts = [c.text for c in chunks]
    logger.info("Embedding %d chunks...", len(texts))
    embeddings = embed_texts(texts)

    metadata = [
        {
            "passage_id": c.passage_id,
            "source_id": c.source_id,
            "subject_id": c.subject_id,
            "chapter_id": c.chapter_id,
            "chapter_title": c.chapter_title,
            "language": c.language,
            "pdf_page_index": c.pdf_page_index,
            "printed_page_label": c.printed_page_label,
            "section_heading": c.section_heading,
            "text": c.text,
            "content_hash": c.content_hash,
            "extraction_method": c.extraction_method,
            "extraction_quality": c.extraction_quality,
        }
        for c in chunks
    ]

    retriever = FAISSRetriever(index_version=index_version)
    retriever.save_index(embeddings, metadata, append=append)
    logger.info("Index version %s saved with %d passages", index_version, len(chunks))
