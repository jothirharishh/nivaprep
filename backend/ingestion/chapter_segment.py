"""
backend/ingestion/chapter_segment.py
Segments extracted pages into chapters based on chapter headings.

TN Samacheer Kalvi Class 10 textbook structure (observed from actual PDFs):
  Page layout on content pages:
    line 0: arabic page number (1, 2, 3, …)
    line 1: EITHER the chapter title (short, title-case)
             OR "10th Standard Science" / "10th Std Mathematics" (running header)
    line 2+: body text

  Chapter openers often have:
    line 1 or 2: "INTRODUCTION", "Learning Outcomes", or "To acquaint ourselves with"
    followed by the chapter title on the next page(s).

  When heuristic detection yields fewer than 2 chapters (e.g. English, Tamil),
  the subject-aware textbook catalog provides the authoritative chapter list
  derived from the official Table of Contents.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Optional

from .pdf_extract import ExtractedPage

logger = logging.getLogger(__name__)


@dataclass
class ChapterSpan:
    chapter_id: str
    chapter_number: int
    title: str
    start_page: int
    end_page: int  # inclusive


# ── Patterns ──────────────────────────────────────────────────────────────────

# Explicit keyword patterns (high confidence)
_KW_CHAPTER_RE = re.compile(r"^CHAPTER\s+(\d{1,2})\s*[:\-–]?\s*(.{0,80})$", re.IGNORECASE)
_KW_UNIT_RE    = re.compile(r"^UNIT\s+(\d{1,2})\s*[:\-–]?\s*(.{0,80})$",    re.IGNORECASE)
_TAMIL_RE      = re.compile(r"^இயல்\s+(\d{1,2})[:\s]*(.*)$")

# Arabic page number alone on a line
_PAGE_NUM_RE   = re.compile(r"^\d{1,3}$")

# Roman numeral page label — front matter
_ROMAN_RE      = re.compile(
    r"^(I{1,3}|IV|V?I{0,3}|IX|X{0,2}I{0,3}|XI{1,3}|XIV|XV|XVI)$",
    re.IGNORECASE,
)

# Running subject header: "10th Standard Science", "10th Std Mathematics"
_RUNNING_SUBJ_RE = re.compile(
    r"^\d{1,2}(th|st|nd|rd)\s+(Std\.?|Standard)\b",
    re.IGNORECASE,
)

# Table of Contents
_TOC_RE = re.compile(r"\b(table\s+of\s+contents|contents)\b", re.IGNORECASE)

# Words and phrases that should NEVER be treated as a chapter title
_NON_TITLE_WORDS = {
    "INTRODUCTION",
    "CONTENTS",
    "TABLE OF CONTENTS",
    "ASSESSMENT",
    "E - BOOK",
    "POINTS TO REMEMBER",
    "ICT CORNER",
    "HOW TO USE THE BOOK",
    "CONCEPT MAP",
    "LEARNING OUTCOMES",
    "NOTE",
    "SYMBOLS",
    "PREFACE",
    "GLOSSARY",
    "SUMMARY",
    "EXERCISE",
    "MODEL QUESTION PAPER",
    "CAREER GUIDANCE",
}

# Plausible chapter-title line: starts with capital letter, 3-65 chars
_TITLE_RE = re.compile(r"^[A-Z][A-Za-z0-9 '\-,\(\)&]{2,63}$")
_NOT_TITLE_ENDINGS = re.compile(r"[.,:;?!]$")

# Sentence openers must be followed by whitespace so they don't match words like 'Thermal'
_SENTENCE_OPENER = re.compile(
    r"^(This|These|The|A|An|In|On|At|By|For|It|When|Where|How|To|If|Each|After)\s+",
    re.IGNORECASE,
)

_UNIT_NUM_RE = re.compile(r"^UNIT\s+\d{1,2}\b", re.IGNORECASE)


# ── Authoritative Catalog for TN Samacheer Kalvi Class 10 Textbooks ───────────
# Used when running-header heuristics find < 2 chapters (e.g. English, Tamil).
# Format: list of (chapter_number, title, start_pdf_page, end_pdf_page)
TN_CLASS_10_CATALOG: dict[str, list[tuple]] = {
    "science": [
        ("sci_ch01", 1,  "Laws of Motion", 8, 22),
        ("sci_ch02", 2,  "Optics", 23, 38),
        ("sci_ch03", 3,  "Thermal Physics", 39, 48),
        ("sci_ch04", 4,  "Electricity", 49, 65),
        ("sci_ch05", 5,  "Acoustics", 66, 80),
        ("sci_ch06", 6,  "Nuclear Physics", 81, 97),
        ("sci_ch07", 7,  "Atoms and Molecules", 98, 112),
        ("sci_ch08", 8,  "Periodic Classification of Elements", 113, 130),
        ("sci_ch09", 9,  "Solutions", 131, 143),
        ("sci_ch10", 10, "Types of Chemical Reactions", 144, 161),
        ("sci_ch11", 11, "Carbon and its Compounds", 162, 179),
        ("sci_ch12", 12, "Plant Anatomy and Plant Physiology", 180, 193),
        ("sci_ch13", 13, "Structural Organisation of Animals", 194, 206),
        ("sci_ch14", 14, "Transportation in Plants and Circulation in Animals", 207, 224),
        ("sci_ch15", 15, "Nervous System", 225, 235),
        ("sci_ch16", 16, "Plant and Animal Hormones", 236, 249),
        ("sci_ch17", 17, "Reproduction in Plants and Animals", 250, 267),
        ("sci_ch18", 18, "Genetics", 268, 280),
        ("sci_ch19", 19, "Origin and Evolution of Life", 281, 292),
        ("sci_ch20", 20, "Breeding and Biotechnology", 293, 306),
        ("sci_ch21", 21, "Health and Diseases", 307, 321),
        ("sci_ch22", 22, "Environmental Management", 322, 335),
        ("sci_ch23", 23, "Visual Communication", 336, 341),
    ],
    "mathematics": [
        ("mat_ch01", 1, "Relations and Functions", 6, 40),
        ("mat_ch02", 2, "Numbers and Sequences", 41, 89),
        ("mat_ch03", 3, "Algebra", 90, 165),
        ("mat_ch04", 4, "Geometry", 166, 207),
        ("mat_ch05", 5, "Coordinate Geometry", 208, 243),
        ("mat_ch06", 6, "Trigonometry", 244, 273),
        ("mat_ch07", 7, "Mensuration", 274, 305),
        ("mat_ch08", 8, "Statistics and Probability", 306, 339),
    ],
    "english": [
        ("eng_u01", 1, "Unit 1: His First Flight", 4, 32),
        ("eng_u02", 2, "Unit 2: The Night the Ghost Got In", 33, 62),
        ("eng_u03", 3, "Unit 3: Empowered Women Navigating the World", 63, 96),
        ("eng_u04", 4, "Unit 4: The Attic", 97, 128),
        ("eng_u05", 5, "Unit 5: Tech Bloomers", 129, 164),
        ("eng_u06", 6, "Unit 6: The Last Lesson", 165, 191),
        ("eng_u07", 7, "Unit 7: The Dying Detective", 192, 221),
    ],
    "social_science": [
        ("his_01", 1,  "History Unit 1: Outbreak of World War I and Its Aftermath", 6, 20),
        ("his_02", 2,  "History Unit 2: The World between two World Wars", 21, 31),
        ("his_03", 3,  "History Unit 3: World War II", 32, 44),
        ("his_04", 4,  "History Unit 4: The World after World War II", 45, 57),
        ("his_05", 5,  "History Unit 5: Social and Religious Reform Movements in the 19th Century", 58, 67),
        ("his_06", 6,  "History Unit 6: Early Revolts against British Rule in Tamil Nadu", 68, 79),
        ("his_07", 7,  "History Unit 7: Anti-Colonial Movements and the Birth of Nationalism", 80, 93),
        ("his_08", 8,  "History Unit 8: Nationalism: Gandhian Phase", 94, 109),
        ("his_09", 9,  "History Unit 9: Freedom Struggle in Tamil Nadu", 110, 119),
        ("his_10", 10, "History Unit 10: Social Transformation in Tamil Nadu", 120, 133),
        ("geo_01", 11, "Geography Unit 1: India - Location, Relief and Drainage", 134, 148),
        ("geo_02", 12, "Geography Unit 2: Climate and Natural Vegetation of India", 149, 158),
        ("geo_03", 13, "Geography Unit 3: India - Agriculture", 159, 174),
        ("geo_04", 14, "Geography Unit 4: India - Resources and Industries", 175, 190),
        ("geo_05", 15, "Geography Unit 5: India - Population, Transport, Communication and Trade", 191, 204),
        ("geo_06", 16, "Geography Unit 6: Physical Geography of Tamil Nadu", 205, 223),
        ("geo_07", 17, "Geography Unit 7: Human Geography of Tamil Nadu", 224, 243),
        ("civ_01", 18, "Civics Unit 1: Indian Constitution", 244, 252),
        ("civ_02", 19, "Civics Unit 2: Central Government", 253, 263),
        ("civ_03", 20, "Civics Unit 3: State Government", 264, 273),
        ("civ_04", 21, "Civics Unit 4: India’s Foreign Policy", 274, 282),
        ("civ_05", 22, "Civics Unit 5: India’s International Relations", 283, 296),
        ("eco_01", 23, "Economics Unit 1: Gross Domestic Product and its Growth: an Introduction", 297, 307),
        ("eco_02", 24, "Economics Unit 2: Globalization and Trade", 308, 315),
        ("eco_03", 25, "Economics Unit 3: Food Security and Nutrition", 316, 325),
        ("eco_04", 26, "Economics Unit 4: Government and Taxes", 326, 332),
        ("eco_05", 27, "Economics Unit 5: Industrial Clusters in Tamil Nadu", 333, 343),
    ],
    "tamil": [
        ("tam_ch01", 1, "இயல் 1: அமுதஊற்று — அன்னை மொழியே / தமிழ்ச்சொல் வளம்", 10, 31),
        ("tam_ch02", 2, "இயல் 2: உயிரின் ஓசை — கேட்கிறதா என் குரல்! / பரிபாடல்", 32, 53),
        ("tam_ch03", 3, "இயல் 3: கூட்டாஞ்சோறு — விருந்து போற்றுதும்! / காசிக்காண்டம்", 54, 79),
        ("tam_ch04", 4, "இயல் 4: மணற்கேணி — மொழிபெயர்ப்புக் கல்வி / திருவிளையாடற் புராணம்", 80, 101),
        ("tam_ch05", 5, "இயல் 5: நிலா முற்றம் — பன்முகக் கலைஞர் / கம்பராமாயணம்", 102, 129),
        ("tam_ch06", 6, "இயல் 6: விதை நெல் — சிற்றகல் ஒளி / சிலப்பதிகாரம்", 130, 151),
        ("tam_ch07", 7, "இயல் 7: பெருவழி — சங்க இலக்கியத்தில் அறம் / தேம்பாவணி", 152, 182),
    ],
}


def _is_roman_page(page: ExtractedPage) -> bool:
    label = page.printed_page_label.strip()
    return bool(_ROMAN_RE.match(label))


def _is_toc_page(page: ExtractedPage) -> bool:
    return bool(_TOC_RE.search(page.text[:400]))


def _is_chapter_opener(lines: list[str]) -> bool:
    """Check if page starts with an introductory heading (e.g. INTRODUCTION, Learning Outcomes)."""
    for line in lines[:4]:
        s = line.strip().upper()
        if s in ("INTRODUCTION", "LEARNING OUTCOMES") or "TO ACQUAINT OURSELVES WITH" in s:
            return True
        if _UNIT_NUM_RE.match(s):
            return True
    return False


def _is_plausible_chapter_title(line: str) -> bool:
    s = line.strip()
    if not s or len(s) < 3 or len(s) > 65:
        return False
    if s.upper() in _NON_TITLE_WORDS:
        return False
    if _NOT_TITLE_ENDINGS.search(s):
        return False
    if not s[0].isupper():
        return False
    if _SENTENCE_OPENER.match(s):
        return False
    if _RUNNING_SUBJ_RE.match(s):
        return False
    if not _TITLE_RE.match(s):
        return False
    return True


def _extract_keyword_chapter(lines: list[str]) -> Optional[tuple[int, str]]:
    """Check for explicit Chapter/Unit keyword — highest confidence."""
    for line in lines[:8]:
        for pat in (_KW_CHAPTER_RE, _KW_UNIT_RE, _TAMIL_RE):
            m = pat.match(line)
            if m:
                try:
                    ch_num = int(m.group(1))
                except (ValueError, IndexError):
                    continue
                if not 1 <= ch_num <= 40:
                    continue
                raw = m.group(2).strip() if len(m.groups()) > 1 else ""
                return ch_num, raw or f"Chapter {ch_num}"
    return None


def _get_running_header(lines: list[str]) -> Optional[str]:
    """
    Extract the running chapter-title header from line 1 (after page number).
    Returns None if line 0 is not a page number, or line 1 is the subject header.
    """
    if not lines:
        return None
    if not _PAGE_NUM_RE.match(lines[0]):
        return None
    if len(lines) < 2:
        return None
    line1 = lines[1].strip()

    # Skip multi-line subject running header like: line 1 = '10', line 2 = 'th Standard Science'
    if len(lines) > 2 and line1 == "10" and "Standard" in lines[2]:
        return None

    # Skip standard subject running header
    if _RUNNING_SUBJ_RE.match(line1):
        return None

    # Must look like a valid chapter title
    if _is_plausible_chapter_title(line1):
        return line1
    return None


def detect_chapter_boundaries(
    pages: list[ExtractedPage],
    subject_id: Optional[str] = None,
) -> list[ChapterSpan]:
    """
    Scan pages for chapter boundaries and return a list of ChapterSpans.

    Strategy:
      1. Explicit keyword: "Chapter N", "Unit N", "இயல் N" anywhere in first 8 lines.
      2. Running-header + Opener detection: Tracks chapter openers like 'INTRODUCTION'
         and maps them to the chapter titles on subsequent pages.
      3. Curated catalog fallback: If heuristics find < 2 chapters and subject_id is
         provided, uses the authoritative Class 10 textbook catalog clipped to the
         available page range.
    """
    spans: list[ChapterSpan] = []
    current_span: Optional[ChapterSpan] = None
    seen_chapter_numbers: set[int] = set()

    # --- Pass 1: Try keyword strategy ---
    keyword_found = False
    for page in pages:
        if page.needs_ocr or _is_roman_page(page) or _is_toc_page(page):
            continue
        lines = [l.strip() for l in page.text.split("\n") if l.strip()]
        result = _extract_keyword_chapter(lines)
        if result:
            keyword_found = True
            break

    if keyword_found:
        logger.info("Using explicit Chapter/Unit keyword detection")
        for page in pages:
            if page.needs_ocr or _is_roman_page(page) or _is_toc_page(page):
                continue
            lines = [l.strip() for l in page.text.split("\n") if l.strip()]
            result = _extract_keyword_chapter(lines)
            if not result:
                continue
            ch_num, ch_title = result
            if ch_num in seen_chapter_numbers:
                continue
            seen_chapter_numbers.add(ch_num)
            if current_span:
                current_span.end_page = page.pdf_page_index - 1
                spans.append(current_span)
            current_span = ChapterSpan(
                chapter_id=f"ch_{ch_num:02d}",
                chapter_number=ch_num,
                title=ch_title,
                start_page=page.pdf_page_index,
                end_page=page.pdf_page_index,
            )

    else:
        # --- Pass 2: Running-header + Opener change detection ---
        logger.info("Using running-header and chapter opener detection")
        prev_header: Optional[str] = None
        pending_opener_page: Optional[int] = None
        ch_counter = 0

        for page in pages:
            if page.needs_ocr or _is_roman_page(page) or _is_toc_page(page):
                continue
            lines = [l.strip() for l in page.text.split("\n") if l.strip()]
            if not lines or not _PAGE_NUM_RE.match(lines[0]):
                continue

            # Check if this page is a chapter opener (e.g. INTRODUCTION)
            if _is_chapter_opener(lines):
                if pending_opener_page is None:
                    if current_span:
                        current_span.end_page = page.pdf_page_index - 1
                        spans.append(current_span)
                        current_span = None
                    pending_opener_page = page.pdf_page_index
                continue

            header = _get_running_header(lines)
            if header is None:
                continue

            if header != prev_header:
                start_p = pending_opener_page if pending_opener_page is not None else page.pdf_page_index
                if current_span:
                    current_span.end_page = start_p - 1
                    spans.append(current_span)
                ch_counter += 1
                prev_header = header
                pending_opener_page = None
                current_span = ChapterSpan(
                    chapter_id=f"ch_{ch_counter:02d}",
                    chapter_number=ch_counter,
                    title=header,
                    start_page=start_p,
                    end_page=page.pdf_page_index,
                )
            elif current_span:
                current_span.end_page = page.pdf_page_index

    if current_span and pages:
        last_real = [p for p in pages if not _is_roman_page(p)]
        current_span.end_page = last_real[-1].pdf_page_index if last_real else pages[-1].pdf_page_index
        spans.append(current_span)

    # --- Pass 3: Curated Catalog Fallback ---
    # Use authoritative textbook catalog if available and either:
    # 1. Fewer than 2 chapters were detected by heuristics, or
    # 2. Subject is social_science, english, or tamil (where running headers lack unit numbers or keyword indicators), or
    # 3. No explicit keyword headers were found in the text.
    should_use_catalog = bool(
        subject_id and subject_id in TN_CLASS_10_CATALOG and (
            len(spans) < 2
            or subject_id in ("social_science", "english", "tamil", "mathematics", "science")
            or not keyword_found
        )
    )

    if should_use_catalog:
        logger.info(
            "Using authoritative textbook catalog for '%s' (heuristics found %d spans, keyword_found=%s)",
            subject_id,
            len(spans),
            keyword_found,
        )
        catalog_spans: list[ChapterSpan] = []
        extracted_indices = {p.pdf_page_index for p in pages}
        for item in TN_CLASS_10_CATALOG[subject_id]:
            if len(item) == 5:
                ch_id, ch_num, ch_title, ch_start, ch_end = item
            else:
                ch_num, ch_title, ch_start, ch_end = item
                ch_id = f"ch_{ch_num:02d}"

            # Only include chapters that actually contain extracted pages
            matching_pages = [idx for idx in extracted_indices if ch_start <= idx <= ch_end]
            if matching_pages:
                actual_start = min(matching_pages)
                actual_end = max(matching_pages)
                catalog_spans.append(
                    ChapterSpan(
                        chapter_id=ch_id,
                        chapter_number=ch_num,
                        title=ch_title,
                        start_page=actual_start,
                        end_page=actual_end,
                    )
                )
        if catalog_spans:
            spans = catalog_spans

    logger.info("Detected %d chapter span(s)", len(spans))
    for s in spans:
        logger.info("  ch%02d '%s'  pages %d–%d", s.chapter_number, s.title, s.start_page, s.end_page)
    return spans


def assign_pages_to_chapters(
    pages: list[ExtractedPage],
    known_spans: list[ChapterSpan],
) -> dict[str, list[ExtractedPage]]:
    """Group pages by chapter_id using known page ranges."""
    grouped: dict[str, list[ExtractedPage]] = {span.chapter_id: [] for span in known_spans}
    unassigned = 0

    for page in pages:
        placed = False
        for span in known_spans:
            if span.start_page <= page.pdf_page_index <= span.end_page:
                grouped[span.chapter_id].append(page)
                placed = True
                break
        if not placed:
            unassigned += 1

    if unassigned:
        logger.debug("%d pages not assigned to any chapter (front-matter) — skipped", unassigned)

    return grouped
