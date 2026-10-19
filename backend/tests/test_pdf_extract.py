"""
backend/tests/test_pdf_extract.py
Unit tests for PDF extraction module using PyMuPDF.
"""
import pytest
from pathlib import Path

from backend.ingestion.pdf_extract import extract_pdf, ExtractedPage, ExtractionReport


def test_extract_pdf_file_not_found():
    with pytest.raises(FileNotFoundError):
        extract_pdf("non_existent_file.pdf")


def test_extract_pdf_real_doc(tmp_path):
    import pymupdf

    # Create a small valid synthetic PDF
    pdf_path = tmp_path / "test_sample.pdf"
    doc = pymupdf.open()
    page1 = doc.new_page()
    page1.insert_text((50, 72), "Tamil Nadu State Board Class 10 Science Textbook.\nChapter 1 Laws of Motion.")
    page2 = doc.new_page()
    page2.insert_text((50, 72), "Inertia depends on mass. Force equals mass times acceleration in every physical situation.")
    doc.save(str(pdf_path))
    doc.close()

    report = extract_pdf(pdf_path)
    assert report.total_pages == 2
    assert len(report.extracted_pages) == 2
    assert "Laws of Motion" in report.extracted_pages[0].text
    assert "Inertia" in report.extracted_pages[1].text
    assert report.extraction_rate == 1.0
