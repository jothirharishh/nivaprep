"""
backend/models/passage.py
Passage / chunk data model (a unit of extracted textbook content).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class ExtractionMethod(str, Enum):
    PYMUPDF = "pymupdf"
    OCR = "ocr"
    MANUAL = "manual"


class ExtractionQuality(str, Enum):
    UNREVIEWED = "unreviewed"
    REVIEWED = "reviewed"
    LOW_QUALITY = "low_quality"
    REJECTED = "rejected"


@dataclass
class Passage:
    passage_id: str
    source_id: str
    subject_id: str
    chapter_id: str
    chapter_title: str
    language: str
    pdf_page_index: int        # 0-based PDF page index
    printed_page_label: str    # 1-based printed/scanned page label
    text: str
    extraction_method: ExtractionMethod
    extraction_quality: ExtractionQuality
    content_hash: str
    section_heading: Optional[str] = None
    embedding_model: Optional[str] = None
    index_version: Optional[str] = None

    def validate(self) -> list[str]:
        errors: list[str] = []
        if not self.passage_id:
            errors.append("passage_id must not be empty")
        if not self.source_id:
            errors.append("source_id must not be empty")
        if not self.text or not self.text.strip():
            errors.append("text must not be empty")
        if self.pdf_page_index < 0:
            errors.append("pdf_page_index must be >= 0")
        if len(self.text) > 8000:
            errors.append("text exceeds maximum allowed length of 8000 characters")
        return errors

    def to_dict(self) -> dict:
        return {
            "passage_id": self.passage_id,
            "source_id": self.source_id,
            "subject_id": self.subject_id,
            "chapter_id": self.chapter_id,
            "chapter_title": self.chapter_title,
            "language": self.language,
            "pdf_page_index": self.pdf_page_index,
            "printed_page_label": self.printed_page_label,
            "section_heading": self.section_heading,
            "text": self.text,
            "extraction_method": self.extraction_method.value,
            "extraction_quality": self.extraction_quality.value,
            "content_hash": self.content_hash,
            "embedding_model": self.embedding_model,
            "index_version": self.index_version,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "Passage":
        return cls(
            passage_id=data["passage_id"],
            source_id=data["source_id"],
            subject_id=data["subject_id"],
            chapter_id=data["chapter_id"],
            chapter_title=data["chapter_title"],
            language=data.get("language", "en"),
            pdf_page_index=int(data["pdf_page_index"]),
            printed_page_label=str(data.get("printed_page_label", "")),
            text=data["text"],
            extraction_method=ExtractionMethod(
                data.get("extraction_method", ExtractionMethod.PYMUPDF.value)
            ),
            extraction_quality=ExtractionQuality(
                data.get("extraction_quality", ExtractionQuality.UNREVIEWED.value)
            ),
            content_hash=data.get("content_hash", ""),
            section_heading=data.get("section_heading"),
            embedding_model=data.get("embedding_model"),
            index_version=data.get("index_version"),
        )
