"""
scripts/debug_chapters.py
Quick debug: print first 8 lines of each page so you can see what
the chapter detector sees and tune patterns accordingly.

Usage:
    python scripts/debug_chapters.py --subject science --max-pages 40
    python scripts/debug_chapters.py --pdf EN/yourfile.pdf --max-pages 40
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from backend.ingestion.pdf_extract import extract_pdf
from backend.ingestion.chapter_segment import detect_chapter_boundaries

DEFAULT_PDFS = {
    "science": "EN/Class_10_Science_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
    "mathematics": "EN/Class_10_Mathematics_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
    "english": "EN/Class_10_English_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
    "social_science": "EN/Class_10_Social_Science_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
    "tamil": "EN/Class_10_Tamil_Tamil_Medium-2025_Edition-www.tntextbooks.in.pdf",
}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--subject", default="science")
    parser.add_argument("--pdf", default=None)
    parser.add_argument("--max-pages", type=int, default=50)
    args = parser.parse_args()

    pdf = args.pdf or DEFAULT_PDFS.get(args.subject)
    path = PROJECT_ROOT / pdf

    print(f"\nExtracting {args.max_pages} pages from: {path.name}\n{'='*70}")
    report = extract_pdf(path, page_start=0, page_end=args.max_pages)

    for page in report.extracted_pages:
        lines = [l.strip() for l in page.text.split("\n") if l.strip()][:8]
        print(f"\n--- Page {page.pdf_page_index} (printed={page.printed_page_label}, words={page.word_count}) ---")
        for i, line in enumerate(lines):
            safe = line.encode('ascii', 'replace').decode('ascii')
            print(f"  L{i}: {safe!r}")

    print(f"\n{'='*70}")
    spans = detect_chapter_boundaries(report.extracted_pages, subject_id=args.subject)
    print(f"\nDETECTED {len(spans)} chapter(s):")
    for s in spans:
        print(f"  ch{s.chapter_number:02d} '{s.title}'  pages {s.start_page}–{s.end_page}")
