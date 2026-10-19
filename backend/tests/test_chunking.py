"""
backend/tests/test_chunking.py
Unit tests for text chunking and page extraction models.
"""
from backend.ingestion.pdf_extract import ExtractedPage, ExtractionReport
from backend.ingestion.chunk import (
    chunk_pages,
    _sliding_window,
    _extract_section_heading,
)


def test_sliding_window():
    text = "The quick brown fox jumps over the lazy dog. A second sentence is needed here. And a third sentence follows."
    # Chunk size 50, overlap 10
    chunks = _sliding_window(text, 50, 10)
    assert len(chunks) > 1
    # Check that joined chunks cover text
    assert "quick brown" in chunks[0]


def test_extract_section_heading():
    text = "1.1 Introduction to Newton's Laws\nHere is the paragraph text."
    heading = _extract_section_heading(text)
    assert heading is not None
    assert "1.1" in heading

    text_no_heading = "Just a regular sentence without section number or caps."
    assert _extract_section_heading(text_no_heading) is None


def test_chunk_pages_normal():
    pages = [
        ExtractedPage(
            pdf_page_index=0,
            printed_page_label="1",
            text="Newton's first law states that an object will remain at rest or in uniform motion unless acted upon by a net external force. This property is known as inertia.",
            word_count=28,
            char_count=165,
            needs_ocr=False,
            content_hash="abc1",
        ),
        ExtractedPage(
            pdf_page_index=1,
            printed_page_label="2",
            text="Newton's second law relates force, mass, and acceleration as F = ma. Momentum is defined as the product of mass and velocity.",
            word_count=22,
            char_count=127,
            needs_ocr=False,
            content_hash="abc2",
        ),
    ]

    chunks = chunk_pages(
        pages=pages,
        source_id="src_sci",
        subject_id="science",
        chapter_id="sci_ch01",
        chapter_title="Laws of Motion",
        chunk_size=100,
        overlap=20,
    )

    assert len(chunks) >= 2
    for c in chunks:
        assert c.source_id == "src_sci"
        assert c.subject_id == "science"
        assert c.chapter_id == "sci_ch01"
        assert c.passage_id.startswith("pas_")
        assert len(c.content_hash) == 64  # SHA256 length


def test_chunk_pages_skips_ocr():
    pages = [
        ExtractedPage(
            pdf_page_index=0,
            printed_page_label="1",
            text="Empty or scanned page",
            word_count=4,
            char_count=22,
            needs_ocr=True,  # Needs OCR -> should be skipped
            content_hash="ocr1",
        )
    ]

    chunks = chunk_pages(
        pages=pages,
        source_id="src_sci",
        subject_id="science",
        chapter_id="sci_ch01",
        chapter_title="Laws of Motion",
    )

    assert len(chunks) == 0


def test_extraction_report_properties():
    report = ExtractionReport(source_path="sample.pdf", total_pages=10)
    assert report.extraction_rate == 0.0

    report.extracted_pages.append(
        ExtractedPage(
            pdf_page_index=0,
            printed_page_label="1",
            text="Valid textbook page with more than ten words of content right here.",
            word_count=12,
            char_count=70,
            needs_ocr=False,
            content_hash="hash",
        )
    )
    assert report.extraction_rate == 0.1
