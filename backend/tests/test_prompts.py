"""
backend/tests/test_prompts.py
Unit tests for prompt templates and prompt builders.
"""
from backend.rag.prompts import (
    MCQ_PROMPT_VERSION,
    QA_PROMPT_VERSION,
    MCQ_SYSTEM_PROMPT,
    QA_SYSTEM_PROMPT,
    build_mcq_user_prompt,
    build_qa_user_prompt,
)


def test_mcq_prompt_builder():
    passages = [
        {
            "passage_id": "pas_101",
            "printed_page_label": "5",
            "text": "The SI unit of force is Newton (N).",
        },
        {
            "passage_id": "pas_102",
            "printed_page_label": "6",
            "text": "One Newton is the force needed to accelerate 1 kg of mass at 1 m/s^2.",
        },
    ]

    prompt = build_mcq_user_prompt(
        passages=passages,
        subject="Science",
        chapter_title="Laws of Motion",
    )

    assert "Subject: Science" in prompt
    assert "Chapter: Laws of Motion" in prompt
    assert "pas_101" in prompt
    assert "The SI unit of force is Newton" in prompt
    assert "Generate one high-quality MCQ based strictly on the evidence above." in prompt


def test_qa_prompt_builder():
    passages = [
        {
            "passage_id": "pas_201",
            "printed_page_label": "12",
            "text": "Photosynthesis occurs in chloroplasts.",
        }
    ]

    prompt = build_qa_user_prompt(
        question="Where does photosynthesis occur?",
        passages=passages,
        subject="Science",
        chapter_title="Plant Anatomy and Plant Physiology",
    )

    assert "Student question: Where does photosynthesis occur?" in prompt
    assert "pas_201" in prompt
    assert "Photosynthesis occurs in chloroplasts." in prompt


def test_system_prompts_contain_strict_rules():
    assert "Tamil Nadu Samacheer Kalvi Class 10" in MCQ_SYSTEM_PROMPT
    assert "abstained" in MCQ_SYSTEM_PROMPT
    assert "abstained" in QA_SYSTEM_PROMPT
    assert MCQ_PROMPT_VERSION.startswith("mcq-")
    assert QA_PROMPT_VERSION.startswith("qa-")
