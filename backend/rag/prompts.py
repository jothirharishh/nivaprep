"""
backend/rag/prompts.py
Prompt templates for MCQ generation and textbook Q&A.
Prompt versions are tracked so generated items can be audited.
"""
from __future__ import annotations

MCQ_PROMPT_VERSION = "mcq-v1"
QA_PROMPT_VERSION = "qa-v1"

MCQ_SYSTEM_PROMPT = """\
You are an expert question-generation assistant for Tamil Nadu Samacheer Kalvi Class 10 textbooks.
Your task is to create multiple-choice questions (MCQs) grounded ONLY in the evidence passages provided.

Rules:
- Use ONLY facts, laws, definitions, and formulas stated explicitly in the provided passages.
- Do NOT use general knowledge, assumptions, or facts not in the passages.
- DIRECT EXAM PHRASING: Write natural, direct exam-style questions (e.g. 'What is the SI unit of electric potential?', 'Which formula represents Ohm\'s law?').
- STRICTLY FORBIDDEN: NEVER start questions with or include meta-phrases such as 'According to the passage', 'Based on the text', 'As stated in the passage', 'In the given passage', or 'According to the excerpt'. Write as an authentic textbook board exam question.
- DIVERSITY & UNIQUENESS: Never repeat any previously asked question. Never rephrase, invert, or ask about the exact same statement or concept as a previous question. Each question must test a novel, distinct concept, law, definition, formula, or application.
- Each question must have exactly 4 options (A, B, C, D) with exactly one correct answer.
- Options must be distinct (no near-duplicates after trimming whitespace).
- The correct answer must be directly supported by a specific passage.
- IN-DEPTH PEDAGOGICAL EXPLANATION: The explanation must be comprehensive and educational (2 to 4 sentences). Clearly state the textbook concept, law, definition, or formula that proves the correct answer. When applicable, explain why other options are incorrect or clarify common student misconceptions to reinforce learning.
- If the passages do not support a good MCQ, respond with {"abstained": true, "reason": "..."}.
- Respond ONLY with valid JSON. Do not include any markdown, code fences, or explanation outside JSON.

Output format (one question):
{
  "abstained": false,
  "question_text": "...",
  "options": [
    {"option_id": "A", "text": "..."},
    {"option_id": "B", "text": "..."},
    {"option_id": "C", "text": "..."},
    {"option_id": "D", "text": "..."}
  ],
  "correct_option_id": "A",
  "explanation": "Detailed explanation (2-4 sentences) explaining why the correct answer is right based on textbook principles/formulas, and providing context on why alternative options are incorrect.",
  "source_passage_ids": ["pas_id_1"],
  "difficulty": "medium"
}
"""

QA_SYSTEM_PROMPT = """\
You are a textbook assistant for Tamil Nadu Samacheer Kalvi Class 10 students.
Answer questions using ONLY the provided textbook passages.

Rules:
- Use ONLY information explicitly stated in the provided passages.
- Cite passage IDs in your response.
- If the passages do not contain enough information, respond with {"abstained": true, "reason": "The selected textbook content did not provide sufficient evidence to answer this question."}.
- Do NOT fabricate facts, page numbers, or citations.
- Respond ONLY with valid JSON.

Output format:
{
  "abstained": false,
  "answer": "...",
  "source_passage_ids": ["pas_id_1"],
  "confidence_note": "Direct quote or paraphrase from passage."
}
"""


def build_mcq_user_prompt(
    passages: list[dict],
    subject: str,
    chapter_title: str,
    existing_questions: list[str] | None = None,
) -> str:
    """Build the user turn for MCQ generation, instructing the model to avoid repeats."""
    passages_text = "\n\n".join(
        f"[PASSAGE ID: {p['passage_id']} | Page: {p.get('printed_page_label', '?')}]\n{p['text']}"
        for p in passages
    )
    blacklist_block = ""
    if existing_questions:
        # Take the most recent questions to keep context size efficient
        recent = [q.strip() for q in existing_questions if q.strip()][-10:]
        if recent:
            items = "\n".join(f"- {q}" for q in recent)
            blacklist_block = (
                f"\n\nPREVIOUSLY ASKED QUESTIONS (DO NOT REPEAT OR REPHRASE ANY OF THESE):\n{items}\n\n"
                "CRITICAL: The question you generate MUST test a completely DIFFERENT fact, law, definition, formula, or concept from the evidence passages."
            )

    subject_lower = subject.lower().strip()
    subject_guidelines = ""
    if subject_lower == "tamil":
        subject_guidelines = (
            "\n\nTAMIL 1-MARK EXAM PATTERNS (Based on question.md):\n"
            "- Write the question_text, all 4 options, and explanation ENTIRELY in Tamil (தமிழ்).\n"
            "- Choose one of the 7 authentic Tamil board exam question patterns:\n"
            "  1. Literary facts: நூலின் ஆசிரியர் யார்? / இப்பாடல் இடம்பெற்றுள்ள நூல் எது? (Author-work pairs)\n"
            "  2. Sound & Poetic meter: பாடலில் அமைந்துள்ள ஓசை, யாப்பு, சீர், மோனை, எதுகை, இயைபு நயம்\n"
            "  3. Grammar identification: இலக்கணக் குறிப்பு (வேற்றுமை உருபு, தொழிற்பெயர், வினையாலணையும் பெயர், பெயரெச்சம்)\n"
            "  4. Word meaning: கொடுக்கப்பட்ட சொல்லின் பொருள் யாது? (Textbook vocabulary / அரும்பொருள்)\n"
            "  5. Correct line or quotation: பாடலின் சரியான அடி/வரியைத் தேர்ந்தெடுக்க\n"
            "  6. Grammar transformation: வேர்ச் சொல், விளித்தொடர், தொடர் வகைகள்\n"
            "  7. Statement comparison: கூற்று மற்றும் காரணத்தை ஆராய்ந்து சரியான விடையைத் தேர்வு செய்க\n"
        )
    elif subject_lower in ("mathematics", "maths"):
        subject_guidelines = (
            "\n\nMATHEMATICS 1-MARK EXAM PATTERNS (Based on question.md):\n"
            "- Select one of the 4 cognitive types:\n"
            "  * Type A (Recall): Definitions, properties, standard results, identity matrices, collinearity\n"
            "  * Type B (Direct calculation): Formula substitution, evaluating values, order of transpose\n"
            "  * Type C (Application): Word problem translated into equation, diagram, or probability\n"
            "  * Type D (Reverse reasoning): Given a condition or result, work backwards to find unknown k\n"
        )
    elif subject_lower == "science":
        subject_guidelines = (
            "\n\nSCIENCE 1-MARK EXAM PATTERNS (Based on question.md):\n"
            "- Cover one of the 4 pillars:\n"
            "  * Definition / Law: SI units, periodic law, Newton's laws, fundamental definitions\n"
            "  * Property / Sign convention: Image nature, focal length sign, valence, states\n"
            "  * Cause-and-Effect Reasoning: 'Why does...', scientific mechanisms\n"
            "  * Proportionality / Numerical: 'If variable X doubles/halves, what happens to Y?'\n"
        )
    elif subject_lower == "english":
        subject_guidelines = (
            "\n\nENGLISH 1-MARK EXAM PATTERNS (Based on question.md):\n"
            "- Choose from: Synonyms, Antonyms, Word formation (plurals/prefixes/suffixes/compounds), Grammar cloze (prepositions/tenses/phrasal verbs), or Abbreviations.\n"
        )
    elif subject_lower in ("social_science", "social"):
        subject_guidelines = (
            "\n\nSOCIAL SCIENCE 1-MARK EXAM PATTERNS (Based on question.md):\n"
            "- Choose from: Leader/reformer identification, Book/author pair, Historical event/treaty, Chronological date/year, Geographic cause/resource, Constitutional institution, or Sector classification.\n"
        )

    return (
        f"Subject: {subject}\nChapter: {chapter_title}\n\n"
        f"Evidence passages:\n{passages_text}"
        f"{blacklist_block}"
        f"{subject_guidelines}\n\n"
        "Generate one high-quality MCQ based strictly on the evidence above. "
        "Provide a detailed, educational explanation (2-4 sentences) explaining why the correct answer is true according to the textbook and why other options do not apply. "
        "Do NOT use meta-phrases like 'According to the passage'."
    )


def build_qa_user_prompt(
    question: str, passages: list[dict], subject: str, chapter_title: str
) -> str:
    """Build the user turn for textbook Q&A."""
    passages_text = "\n\n".join(
        f"[PASSAGE ID: {p['passage_id']} | Page: {p.get('printed_page_label', '?')}]\n{p['text']}"
        for p in passages
    )
    return (
        f"Subject: {subject}\nChapter: {chapter_title}\n\n"
        f"Evidence passages:\n{passages_text}\n\n"
        f"Student question: {question}"
    )
