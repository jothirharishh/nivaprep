"""
backend/ingestion/pdf_extract.py
PDF text extraction using PyMuPDF (fitz).
Produces page-level text with metadata.
"""
from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


@dataclass
class ExtractedPage:
    pdf_page_index: int       # 0-based
    printed_page_label: str   # label from PDF metadata or str(pdf_page_index + 1)
    text: str
    word_count: int
    char_count: int
    needs_ocr: bool           # True if page looks empty/scanned
    content_hash: str


@dataclass
class ExtractionReport:
    source_path: str
    total_pages: int
    extracted_pages: list[ExtractedPage] = field(default_factory=list)
    empty_pages: list[int] = field(default_factory=list)
    low_text_pages: list[int] = field(default_factory=list)
    ocr_candidates: list[int] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)

    @property
    def extraction_rate(self) -> float:
        if self.total_pages == 0:
            return 0.0
        usable = sum(1 for p in self.extracted_pages if not p.needs_ocr and p.word_count > 10)
        return usable / self.total_pages


_LOW_TEXT_THRESHOLD = 50   # chars per page — below this, flag for OCR
_OCR_THRESHOLD = 10        # chars — essentially empty


def extract_pdf(
    pdf_path: str | Path,
    page_start: int = 0,
    page_end: Optional[int] = None,
) -> ExtractionReport:
    """
    Extract text from a PDF file using PyMuPDF.
    page_start and page_end are 0-based page indices (inclusive, exclusive).
    """
    try:
        import pymupdf as fitz
    except ImportError:
        try:
            import fitz  # PyMuPDF legacy fallback
        except ImportError as exc:
            raise ImportError("PyMuPDF is required. pip install pymupdf") from exc

    # Suppress internal C-level MuPDF error noise (e.g. 'stitching function has no bounds')
    try:
        fitz.TOOLS.mupdf_display_errors(False)
    except Exception:
        pass

    path = Path(pdf_path)
    if not path.exists():
        raise FileNotFoundError(f"PDF not found: {path}")

    report = ExtractionReport(source_path=str(path), total_pages=0)

    try:
        doc = fitz.open(str(path))
    except Exception as exc:
        report.errors.append(f"Failed to open PDF: {exc}")
        return report

    report.total_pages = doc.page_count
    end = page_end if page_end is not None else doc.page_count

    for i in range(page_start, min(end, doc.page_count)):
        try:
            page = doc[i]
            text = page.get_text("text")  # type: ignore[attr-defined]
            label = doc.get_page_labels()  # type: ignore[attr-defined]
            # Fallback page label
            printed_label = str(i + 1)
            try:
                labels = doc.get_page_labels()
                if labels and i < len(labels):
                    printed_label = str(labels[i] or i + 1)
            except Exception:
                pass

            char_count = len(text.strip())
            word_count = len(text.split())
            needs_ocr = char_count < _LOW_TEXT_THRESHOLD
            content_hash = hashlib.sha256(text.encode()).hexdigest()

            ep = ExtractedPage(
                pdf_page_index=i,
                printed_page_label=printed_label,
                text=text,
                word_count=word_count,
                char_count=char_count,
                needs_ocr=needs_ocr,
                content_hash=content_hash,
            )
            report.extracted_pages.append(ep)

            if char_count < _OCR_THRESHOLD:
                report.empty_pages.append(i)
            elif char_count < _LOW_TEXT_THRESHOLD:
                report.low_text_pages.append(i)
            if needs_ocr:
                report.ocr_candidates.append(i)

        except Exception as exc:
            report.errors.append(f"Page {i}: {exc}")
            logger.error("Error extracting page %d: %s", i, exc)

    doc.close()
    logger.info(
        "Extracted %d pages from %s; %d empty, %d low-text, %d OCR candidates",
        len(report.extracted_pages),
        path.name,
        len(report.empty_pages),
        len(report.low_text_pages),
        len(report.ocr_candidates),
    )
    return report
