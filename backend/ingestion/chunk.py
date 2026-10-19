"""
backend/ingestion/chunk.py
Splits extracted page text into overlapping chunks with metadata.
"""
from __future__ import annotations

import hashlib
import logging
import re
import uuid
from dataclasses import dataclass

from .pdf_extract import ExtractedPage

logger = logging.getLogger(__name__)

DEFAULT_CHUNK_SIZE = 500    # target chars per chunk
DEFAULT_OVERLAP = 100       # overlap between consecutive chunks


@dataclass
class Chunk:
    passage_id: str
    source_id: str
    subject_id: str
    chapter_id: str
    chapter_title: str
    language: str
    pdf_page_index: int
    printed_page_label: str
    section_heading: str | None
    text: str
    content_hash: str
    extraction_method: str
    extraction_quality: str


def chunk_pages(
    pages: list[ExtractedPage],
    source_id: str,
    subject_id: str,
    chapter_id: str,
    chapter_title: str,
    language: str = "en",
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    overlap: int = DEFAULT_OVERLAP,
    extraction_method: str = "pymupdf",
) -> list[Chunk]:
    """
    Split a list of extracted pages into overlapping text chunks.
    Skips pages flagged as needing OCR (needs_ocr=True).
    """
    chunks: list[Chunk] = []
    for page in pages:
        if page.needs_ocr:
            logger.debug("Skipping OCR-flagged page %d", page.pdf_page_index)
            continue
        text = page.text.strip()
        if not text:
            continue

        quality = "reviewed" if not page.needs_ocr else "unreviewed"
        heading = _extract_section_heading(text)

        for chunk_text in _sliding_window(text, chunk_size, overlap):
            content_hash = hashlib.sha256(chunk_text.encode()).hexdigest()
            chunk = Chunk(
                passage_id=f"pas_{uuid.uuid4().hex[:12]}",
                source_id=source_id,
                subject_id=subject_id,
                chapter_id=chapter_id,
                chapter_title=chapter_title,
                language=language,
                pdf_page_index=page.pdf_page_index,
                printed_page_label=page.printed_page_label,
                section_heading=heading,
                text=chunk_text,
                content_hash=content_hash,
                extraction_method=extraction_method,
                extraction_quality=quality,
            )
            chunks.append(chunk)

    logger.info("Produced %d chunks from %d pages", len(chunks), len(pages))
    return chunks


def _sliding_window(text: str, size: int, overlap: int) -> list[str]:
    """Split text into overlapping chunks using sentence/paragraph boundaries."""
    sentences = re.split(r"(?<=[.!?])\s+", text)
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        if len(current) + len(sentence) <= size:
            current = (current + " " + sentence).strip() if current else sentence
        else:
            if current:
                chunks.append(current)
            # Start next chunk with overlap from previous
            overlap_text = current[-overlap:] if len(current) > overlap else current
            current = (overlap_text + " " + sentence).strip()
    if current:
        chunks.append(current)
    return chunks if chunks else [text[:size]]


def _extract_section_heading(text: str) -> str | None:
    """Heuristically extract a section heading from the first line."""
    first_line = text.split("\n", 1)[0].strip()
    if 5 < len(first_line) < 120 and not first_line.endswith("."):
        return first_line
    return None
