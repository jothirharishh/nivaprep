"""
scripts/ingest_textbooks.py
CLI tool to ingest a textbook PDF into chapters, passages, and FAISS index.

Usage:
    # Ingest all 5 textbooks (full — takes time but covers complete content):
    python scripts/ingest_textbooks.py --all

    # Quick dev run (first 30 pages per book, fast):
    python scripts/ingest_textbooks.py --all --max-pages 30

    # Single subject:
    python scripts/ingest_textbooks.py --subject science

    # Custom PDF:
    python scripts/ingest_textbooks.py --pdf path/to/file.pdf --subject science --source-id src_custom
"""
from __future__ import annotations

import argparse
import hashlib
import logging
import sys
from pathlib import Path

# Add project root to sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from backend.ingestion.pdf_extract import extract_pdf, ExtractionReport
from backend.ingestion.chapter_segment import (
    detect_chapter_boundaries,
    assign_pages_to_chapters,
    ChapterSpan,
    TN_CLASS_10_CATALOG,
)
from backend.ingestion.chunk import chunk_pages
from backend.ingestion.index import build_index
from backend.models.source import Source, IngestionStatus, RightsStatus
from backend.repositories.db import init_db, set_database_path, get_db
from backend.repositories.source_repository import ChapterRepository, SourceRepository

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s: %(message)s")
logger = logging.getLogger("ingest")


DEFAULT_EN_TEXTBOOKS = {
    "science": {
        "pdf": "EN/Class_10_Science_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
        "source_id": "src_tn_sci_10_2024",
        "title": "Class 10 Science — English Medium (2024 Edition)",
        "edition": "2024",
    },
    "mathematics": {
        "pdf": "EN/Class_10_Mathematics_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
        "source_id": "src_tn_mat_10_2025",
        "title": "Class 10 Mathematics — English Medium (2025 Edition)",
        "edition": "2025",
    },
    "english": {
        "pdf": "EN/Class_10_English_English_Medium-2024_Edition-www.tntextbooks.in.pdf",
        "source_id": "src_tn_eng_10_2024",
        "title": "Class 10 English — English Medium (2024 Edition)",
        "edition": "2024",
    },
    "social_science": {
        "pdf": "EN/Class_10_Social_Science_English_Medium-2025_Edition-www.tntextbooks.in.pdf",
        "source_id": "src_tn_soc_10_2025",
        "title": "Class 10 Social Science — English Medium (2025 Edition)",
        "edition": "2025",
    },
    "tamil": {
        "pdf": "EN/Class_10_Tamil_Tamil_Medium-2025_Edition-www.tntextbooks.in.pdf",
        "source_id": "src_tn_tam_10_2025",
        "title": "Class 10 Tamil — Tamil Medium (2025 Edition)",
        "edition": "2025",
    },
}


def _compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(65536), b""):
            h.update(block)
    return h.hexdigest()


def ingest_pdf(
    pdf_path: str | Path,
    subject_id: str,
    source_id: str,
    title: str = "",
    edition: str = "unknown",
    max_pages: int | None = None,
    page_start: int = 0,
    page_end: int | None = None,
    page_ranges: list[tuple[int, int]] | None = None,
    db_path: str | None = None,
    index_version: str = "v1",
    append_index: bool = True,
    remove_stored_questions: bool = False,
) -> None:
    if db_path is None:
        db_path = str(PROJECT_ROOT / "backend" / "data" / "boardmate.db")

    set_database_path(db_path)
    init_db(db_path)

    if remove_stored_questions:
        with get_db() as conn:
            cursor = conn.execute("DELETE FROM questions WHERE subject_id = ?", (subject_id,))
            logger.info("Removed %d previously stored questions for subject '%s'", cursor.rowcount, subject_id)

    path = Path(pdf_path)
    if not path.is_absolute():
        path = PROJECT_ROOT / path

    if not path.exists():
        logger.error("PDF file not found: %s", path)
        sys.exit(1)

    # ── Register source record ────────────────────────────────────────────────
    # This was previously missing — without this the /v1/subjects/{id}/chapters
    # endpoint would always return an empty list.
    source_repo = SourceRepository()
    existing = source_repo.get_by_id(source_id)
    if existing is None:
        logger.info("Registering source record: %s", source_id)
        sha256 = _compute_sha256(path)
        source = Source(
            source_id=source_id,
            title=title or path.stem,
            subject_id=subject_id,
            edition=edition,
            rights_status=RightsStatus.USER_SUPPLIED_REVIEW_REQUIRED,
            rights_notes=(
                "Tamil Nadu State Board Samacheer Kalvi textbook. "
                "Obtained from tntextbooks.in. Rights review required before any redistribution."
            ),
            ingestion_status=IngestionStatus.IN_PROGRESS,
            source_uri=str(path),
            file_sha256=sha256,
        )
        source_repo.insert(source)
    else:
        logger.info("Source %s already registered — updating status to in_progress", source_id)
        source_repo.update_ingestion_status(source_id, IngestionStatus.IN_PROGRESS)

    # ── Extract PDF text ──────────────────────────────────────────────────────
    if page_ranges:
        logger.info("Extracting PDF text from %d range(s): %s", len(page_ranges), page_ranges)
        all_extracted = []
        all_empty = []
        all_low = []
        all_ocr = []
        all_errors = []
        total_p = 0
        for s, e in page_ranges:
            r = extract_pdf(path, page_start=s, page_end=e)
            all_extracted.extend(r.extracted_pages)
            all_empty.extend(r.empty_pages)
            all_low.extend(r.low_text_pages)
            all_ocr.extend(r.ocr_candidates)
            all_errors.extend(r.errors)
            total_p += r.total_pages
        report = ExtractionReport(
            source_path=str(path),
            total_pages=total_p,
            extracted_pages=all_extracted,
            empty_pages=all_empty,
            low_text_pages=all_low,
            ocr_candidates=all_ocr,
            errors=all_errors,
        )
    else:
        effective_end = page_end if page_end is not None else (page_start + max_pages if max_pages is not None else None)
        logger.info("Extracting PDF text from: %s  (pages=%s to %s)", path.name, page_start, effective_end or "all")
        report = extract_pdf(path, page_start=page_start, page_end=effective_end)

    logger.info(
        "Extraction finished: %d total, %d extracted, %d OCR candidates, rate=%.1f%%",
        report.total_pages,
        len(report.extracted_pages),
        len(report.ocr_candidates),
        report.extraction_rate * 100,
    )

    if not report.extracted_pages:
        logger.warning("No pages extracted. Check the PDF path and PyMuPDF installation.")
        source_repo.update_ingestion_status(source_id, IngestionStatus.FAILED)
        return

    # ── Detect chapter boundaries ─────────────────────────────────────────────
    detected_spans = detect_chapter_boundaries(report.extracted_pages, subject_id=subject_id)
    if not detected_spans:
        logger.warning(
            "No chapters detected by regex heuristics — using single-chapter fallback. "
            "Consider extending chapter_segment.py patterns for this textbook."
        )
        detected_spans = [
            ChapterSpan(
                chapter_id="ch01",
                chapter_number=1,
                title=f"{subject_id.replace('_', ' ').title()} — Full Book",
                start_page=0,
                end_page=len(report.extracted_pages) - 1,
            )
        ]

    # ── Persist chapter records ───────────────────────────────────────────────
    chap_repo = ChapterRepository()
    if not page_ranges and max_pages is None and len(detected_spans) >= 5:
        with get_db() as conn:
            conn.execute("DELETE FROM chapters WHERE subject_id = ?", (subject_id,))
            conn.execute("DELETE FROM passages WHERE subject_id = ?", (subject_id,))
    for span in detected_spans:
        # Avoid double-prefixing if chapter_id is already namespaced with subject prefix
        if span.chapter_id.startswith(("eng_", "tam_", "sci_", "mat_", "soc_")):
            full_chapter_id = span.chapter_id
        else:
            full_chapter_id = f"{source_id}_{span.chapter_id}"

        chap_repo.insert({
            "chapter_id": full_chapter_id,
            "source_id": source_id,
            "subject_id": subject_id,
            "chapter_number": span.chapter_number,
            "title": span.title,
            "start_pdf_page": span.start_page,
            "end_pdf_page": span.end_page,
            "status": "ready",
        })
        logger.info(
            "Chapter: %s — '%s' (pages %d–%d)",
            full_chapter_id, span.title, span.start_page, span.end_page,
        )

    # ── Chunk pages per chapter ───────────────────────────────────────────────
    grouped = assign_pages_to_chapters(report.extracted_pages, detected_spans)
    all_chunks = []
    for span in detected_spans:
        ch_pages = grouped.get(span.chapter_id, [])
        if not ch_pages:
            continue
        if span.chapter_id.startswith(("eng_", "tam_", "sci_", "mat_", "soc_")):
            full_chapter_id = span.chapter_id
        else:
            full_chapter_id = f"{source_id}_{span.chapter_id}"

        chunks = chunk_pages(
            pages=ch_pages,
            source_id=source_id,
            subject_id=subject_id,
            chapter_id=full_chapter_id,
            chapter_title=span.title,
        )
        all_chunks.extend(chunks)

    logger.info("Created %d text chunks across %d chapters", len(all_chunks), len(detected_spans))

    # ── Persist passages to SQLite ────────────────────────────────────────────
    with get_db() as conn:
        chapter_ids_to_clean = {c.chapter_id for c in all_chunks}
        for cid in chapter_ids_to_clean:
            conn.execute("DELETE FROM passages WHERE chapter_id = ?", (cid,))
        for c in all_chunks:
            conn.execute(
                """INSERT OR REPLACE INTO passages (
                    passage_id, source_id, subject_id, chapter_id,
                    chapter_title, language, pdf_page_index, printed_page_label,
                    section_heading, text, extraction_method, extraction_quality,
                    content_hash
                ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (
                    c.passage_id,
                    c.source_id,
                    c.subject_id,
                    c.chapter_id,
                    c.chapter_title,
                    c.language,
                    c.pdf_page_index,
                    c.printed_page_label,
                    c.section_heading,
                    c.text,
                    c.extraction_method,
                    c.extraction_quality,
                    c.content_hash,
                ),
            )
    logger.info("Persisted %d passages to SQLite.", len(all_chunks))

    # ── Build FAISS vector index ──────────────────────────────────────────────
    # This was previously missing — without this the retriever had nothing to search.
    if all_chunks:
        logger.info(
            "Building FAISS index (version=%s, append=%s) — embedding %d chunks, please wait…",
            index_version, append_index, len(all_chunks),
        )
        build_index(all_chunks, index_version=index_version, append=append_index)
        logger.info("FAISS index built and saved.")
    else:
        logger.warning("No chunks produced — FAISS index was not updated.")

    # ── Mark source as completed ──────────────────────────────────────────────
    source_repo.update_ingestion_status(source_id, IngestionStatus.COMPLETED)
    logger.info("✓ Ingestion complete for: %s  (%d passages indexed)", path.name, len(all_chunks))


# ── CLI entry point ────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import re

    parser = argparse.ArgumentParser(
        description="Ingest Samacheer Kalvi Class 10 textbook PDF(s) into BoardMate 10"
    )
    parser.add_argument("--pdf", default=None, help="Path to a specific PDF file")
    parser.add_argument(
        "--subject", default=None,
        help="Subject ID: science, mathematics, english, social_science, tamil",
    )
    parser.add_argument("--source-id", default=None, help="Source ID (uses default if omitted)")
    parser.add_argument("--all", action="store_true", help="Ingest all 5 textbooks from EN/")
    parser.add_argument(
        "--pages", default=None,
        help="1-based page range (e.g. '50-65' or '50:65'). Translates to 0-based indices.",
    )
    parser.add_argument(
        "--page-start", type=int, default=0,
        help="0-based start page index (default: 0).",
    )
    parser.add_argument(
        "--page-end", type=int, default=None,
        help="0-based end page index exclusive.",
    )
    parser.add_argument(
        "--chapter", default=None,
        help="Specific chapter ID or number to ingest (e.g. 'eng_u01', 'eng_u02', 'eng_u03', or '1', '2', '3')",
    )
    parser.add_argument(
        "--max-pages", type=int, default=None,
        help="Maximum pages per textbook (default: all). Pass 30 for quick dev testing.",
    )
    parser.add_argument("--db-path", default=None, help="Override SQLite database path")
    parser.add_argument("--index-version", default="v1", help="FAISS index version tag (default: v1)")
    parser.add_argument(
        "--no-append", action="store_true",
        help="Overwrite existing FAISS index instead of appending new chunks",
    )
    parser.add_argument(
        "--remove-stored-questions", action="store_true",
        help="Remove previously stored questions for this subject before ingesting",
    )
    args = parser.parse_args()

    page_start = args.page_start
    page_end = args.page_end
    page_ranges: list[tuple[int, int]] | None = None

    if args.chapter and args.subject and args.subject in TN_CLASS_10_CATALOG:
        matched = None
        for item in TN_CLASS_10_CATALOG[args.subject]:
            if len(item) == 5:
                cid, cnum, ctitle, cstart, cend = item
            else:
                cnum, ctitle, cstart, cend = item
                cid = f"ch_{cnum:02d}"
            if str(args.chapter) in (cid, str(cnum), f"u0{cnum}", f"ch0{cnum}", f"ch_{cnum:02d}", f"u_{cnum:02d}", f"mat_ch0{cnum}", f"mat_ch{cnum:02d}", f"sci_ch0{cnum}", f"sci_ch{cnum:02d}", f"tam_ch0{cnum}", f"tam_ch{cnum:02d}"):
                matched = (cid, cnum, ctitle, cstart, cend)
                break
        if matched:
            cid, cnum, ctitle, cstart, cend = matched
            logger.info("Targeting single chapter: %s — '%s' (PDF pages %d to %d)", cid, ctitle, cstart, cend)
            page_start = cstart
            page_end = cend + 1
            page_ranges = None
        else:
            logger.error("Chapter '%s' not found in catalog for subject '%s'", args.chapter, args.subject)
            sys.exit(1)
    elif args.pages:
        raw_ranges = [r.strip() for r in args.pages.split(",") if r.strip()]
        parsed_ranges: list[tuple[int, int]] = []
        for r_str in raw_ranges:
            parts = re.split(r"[-:]", r_str)
            p1 = int(parts[0].strip())
            p2 = int(parts[1].strip())
            parsed_ranges.append((p1 - 1, p2))
        if len(parsed_ranges) == 1:
            page_start, page_end = parsed_ranges[0]
        else:
            page_ranges = parsed_ranges

    common_kwargs = dict(
        max_pages=args.max_pages,
        page_start=page_start,
        page_end=page_end,
        page_ranges=page_ranges,
        db_path=args.db_path,
        index_version=args.index_version,
        append_index=not args.no_append,
        remove_stored_questions=args.remove_stored_questions,
    )

    if args.all:
        for subj, meta in DEFAULT_EN_TEXTBOOKS.items():
            logger.info("=== Ingesting %s ===", subj.upper())
            ingest_pdf(
                pdf_path=meta["pdf"],
                subject_id=subj,
                source_id=meta["source_id"],
                title=meta["title"],
                edition=meta["edition"],
                **common_kwargs,
            )
    elif args.subject and args.subject in DEFAULT_EN_TEXTBOOKS and not args.pdf:
        meta = DEFAULT_EN_TEXTBOOKS[args.subject]
        ingest_pdf(
            pdf_path=meta["pdf"],
            subject_id=args.subject,
            source_id=args.source_id or meta["source_id"],
            title=meta["title"],
            edition=meta["edition"],
            **common_kwargs,
        )
    elif args.pdf and args.subject and args.source_id:
        ingest_pdf(
            pdf_path=args.pdf,
            subject_id=args.subject,
            source_id=args.source_id,
            **common_kwargs,
        )
    else:
        parser.print_help()
        print("\nAvailable subjects (EN/ folder):")
        for s, m in DEFAULT_EN_TEXTBOOKS.items():
            print(f"  --subject {s:20} → {m['pdf']}")
        sys.exit(1)
