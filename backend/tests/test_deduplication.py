"""
backend/tests/test_deduplication.py
Unit tests for anti-repetition and anti-rephrasing logic.
"""
from backend.rag.deduplication import (
    normalize_text,
    extract_content_words,
    jaccard_similarity,
    is_duplicate_or_rephrase,
)


def test_normalize_text():
    text1 = "According to Newton's First Law of Motion, what happens...?"
    text2 = "according to newton s first law of motion what happens"
    assert normalize_text(text1) == text2


def test_jaccard_similarity_identical():
    words = {"force", "acceleration", "mass"}
    assert jaccard_similarity(words, words) == 1.0


def test_jaccard_similarity_disjoint():
    words1 = {"force", "acceleration", "mass"}
    words2 = {"plant", "photosynthesis", "chlorophyll"}
    assert jaccard_similarity(words1, words2) == 0.0


def test_exact_duplicate_detected():
    existing = ["What is the SI unit of electric current?"]
    candidate = "What is the SI unit of electric current?"
    is_dup, score, matched = is_duplicate_or_rephrase(candidate, existing)
    assert is_dup is True
    assert score == 1.0
    assert matched == existing[0]


def test_normalized_duplicate_detected():
    existing = ["What is the SI unit of electric current?"]
    candidate = "what is the SI unit of electric current!"
    is_dup, score, matched = is_duplicate_or_rephrase(candidate, existing)
    assert is_dup is True
    assert score == 1.0


def test_high_keyword_rephrase_detected():
    existing = ["Inertia of a body depends on mass of the object."]
    candidate = "The mass of an object determines its body inertia."
    is_dup, score, matched = is_duplicate_or_rephrase(candidate, existing)
    assert is_dup is True
    assert score >= 0.50


def test_distinct_concept_not_flagged():
    existing = [
        "According to Newton's First Law of Motion, a body remains at rest unless acted on by a force.",
        "What is the SI unit of linear momentum?",
    ]
    candidate = "Which law states that the total momentum of an isolated system remains conserved?"
    is_dup, score, matched = is_duplicate_or_rephrase(
        candidate,
        existing,
        semantic_threshold=0.72,
        jaccard_threshold=0.55,
    )
    assert is_dup is False
    assert score < 0.72


def test_tamil_exact_duplicate_detected():
    existing = ["'மெத்த வணிகலன்' என்னும் தொடரில் தமிழழகனார் குறிப்பிடுவது எது?"]
    candidate = "‘மெத்த வணிகலன்’ என்னும் தொடரில் தமிழழகனார் குறிப்பிடுவது எது?"
    is_dup, score, matched = is_duplicate_or_rephrase(candidate, existing)
    assert is_dup is True
    assert score == 1.0


def test_tamil_distinct_questions_not_flagged():
    existing = [
        "'மெத்த வணிகலன்' என்னும் தொடரில் தமிழழகனார் குறிப்பிடுவது எது?",
        "காசிக்காண்டம் என்பது எவ்வகை நூல்?",
    ]
    candidate = "‘அன்னை மொழியே’ பாடலின் ஆசிரியர் யார்?"
    is_dup, score, matched = is_duplicate_or_rephrase(candidate, existing)
    assert is_dup is False

