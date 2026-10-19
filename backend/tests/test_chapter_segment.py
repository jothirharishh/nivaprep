"""
backend/tests/test_chapter_segment.py
Unit tests for chapter segmentation and boundary detection.
"""
from backend.ingestion.pdf_extract import ExtractedPage
from backend.ingestion.chapter_segment import (
    ChapterSpan,
    detect_chapter_boundaries,
    assign_pages_to_chapters,
)


def test_detect_chapter_boundaries():
    pages = [
        ExtractedPage(
            pdf_page_index=0,
            printed_page_label="1",
            text="CHAPTER 1: LAWS OF MOTION\nIn this chapter we study motion.",
            word_count=10,
            char_count=60,
            needs_ocr=False,
            content_hash="h1",
        ),
        ExtractedPage(
            pdf_page_index=1,
            printed_page_label="2",
            text="Continuing laws of motion content...",
            word_count=5,
            char_count=35,
            needs_ocr=False,
            content_hash="h2",
        ),
        ExtractedPage(
            pdf_page_index=2,
            printed_page_label="3",
            text="CHAPTER 2: OPTICS\nIn this chapter we study light.",
            word_count=9,
            char_count=55,
            needs_ocr=False,
            content_hash="h3",
        ),
    ]

    spans = detect_chapter_boundaries(pages)
    assert len(spans) == 2
    assert spans[0].chapter_id == "ch_01"
    assert spans[0].chapter_number == 1
    assert spans[0].title == "LAWS OF MOTION"
    assert spans[0].start_page == 0
    assert spans[0].end_page == 1

    assert spans[1].chapter_id == "ch_02"
    assert spans[1].chapter_number == 2
    assert spans[1].title == "OPTICS"
    assert spans[1].start_page == 2
    assert spans[1].end_page == 2


def test_assign_pages_to_chapters():
    pages = [
        ExtractedPage(
            pdf_page_index=0,
            printed_page_label="1",
            text="Page 1 text",
            word_count=3,
            char_count=11,
            needs_ocr=False,
            content_hash="h1",
        ),
        ExtractedPage(
            pdf_page_index=1,
            printed_page_label="2",
            text="Page 2 text",
            word_count=3,
            char_count=11,
            needs_ocr=False,
            content_hash="h2",
        ),
    ]

    spans = [
        ChapterSpan(chapter_id="ch_01", chapter_number=1, title="Ch 1", start_page=0, end_page=0),
        ChapterSpan(chapter_id="ch_02", chapter_number=2, title="Ch 2", start_page=1, end_page=1),
    ]

    grouped = assign_pages_to_chapters(pages, spans)
    assert len(grouped["ch_01"]) == 1
    assert grouped["ch_01"][0].pdf_page_index == 0
    assert len(grouped["ch_02"]) == 1
    assert grouped["ch_02"][0].pdf_page_index == 1


def test_detect_chapter_boundaries_with_catalog_slice():
    # Simulate a slice of pages in Science for Chapter 4 Electricity (pages 49-64)
    pages = [
        ExtractedPage(
            pdf_page_index=i,
            printed_page_label=str(i + 1),
            text=f"Text for page {i}",
            word_count=20,
            char_count=100,
            needs_ocr=False,
            content_hash=f"hash_{i}",
        )
        for i in range(49, 65)
    ]

    spans = detect_chapter_boundaries(pages, subject_id="science")
    assert len(spans) == 1
    assert spans[0].chapter_id == "sci_ch04"
    assert spans[0].chapter_number == 4
    assert spans[0].title == "Electricity"
    assert spans[0].start_page == 49
    assert spans[0].end_page == 64
