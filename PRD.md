# Product Requirements Document — BoardMate 10

## 1. Summary
BoardMate 10 is an Android study app for Tamil Nadu Samacheer Kalvi Class 10 students. Its first release uses English-medium content across Tamil, English, Mathematics, Science, and Social Science. Students practise one-mark questions from textbook material and additional questions generated from retrieved textbook passages.

## 2. Problem
Students need a reliable way to practise the facts, definitions, concepts, formulae, grammar, dates, and other short-answer content found in their textbooks. Generic AI quizzes may drift away from the syllabus or provide incorrect answers. The product must prioritize textbook alignment, provenance, and answer quality over raw question count.

## 3. Target users
- Primary: a Class 10 student preparing for Tamil Nadu board examinations.
- Secondary: a family member helping curate or review the question bank.
- Future: additional students and teachers, subject to privacy and content-rights considerations.

## 4. Product principles
1. Textbook-first, not general-knowledge-first.
2. Clearly label original textbook, adapted, and AI-generated questions.
3. Attach source metadata to every question.
4. Separate candidate questions from approved questions.
5. Make routine practice fast and available offline.
6. Do not require an account in the MVP.

## 5. MVP scope

### Included
- Android app built with Flutter.
- English question content for all five main subject areas: Tamil, English, Mathematics, Science, Social Science.
- Subject and chapter selection.
- Four-option MCQ practice where suitable for the source material.
- Immediate feedback, correct answer, and short explanation.
- End-of-session score and review.
- Saved local progress and incorrect-question list.
- A backend ingestion pipeline for textbook PDFs.
- RAG retrieval filtered by subject, edition, and chapter.
- Groq-backed generation of candidate questions in a strict JSON schema.
- Validation and review status before a generated question enters the verified bank.
- Source references with page numbers where reliably extracted.

### Out of scope for MVP
- iOS release.
- Public multi-user accounts and social features.
- Payments, ads, leaderboards, and chat between students.
- Training a foundation model from scratch.
- Automatically publishing unreviewed LLM-generated questions as verified.
- Guaranteeing predictions of the actual board exam paper.
- Full Tamil-language UI/content unless separately planned and tested.
- Redis, Kubernetes, microservices, or complex cloud infrastructure without demonstrated need.

## 6. Core user journeys

### Journey A: Practise a chapter
1. Open app.
2. Select subject.
3. Select chapter.
4. Choose textbook questions, approved practice, or mixed practice.
5. Answer questions.
6. Receive feedback and explanation.
7. View score and review mistakes.

### Journey B: Review mistakes
1. Open Mistake Review.
2. See previously incorrect questions.
3. Retry questions.
4. Update progress when answered correctly.
5. Retain history needed for spaced review.

### Journey C: Generate additional practice
1. A maintainer selects a subject, edition, and chapter.
2. The backend retrieves relevant textbook passages.
3. Groq generates candidate questions with source passage IDs.
4. Validation checks structure, answer index, options, evidence, and duplicates.
5. Questions with unresolved issues remain pending review or are rejected.
6. A reviewer approves suitable questions into the practice bank.

### Journey D: Ask the textbook
1. Student asks a question about a selected chapter.
2. The backend retrieves relevant passages.
3. The LLM answers only from the retrieved evidence.
4. The answer includes source references.
5. If evidence is insufficient, the system says it could not find a reliable answer in the selected material.

## 7. Functional requirements
- FR-01: Show all five subject areas.
- FR-02: Display chapters based on the confirmed textbook edition.
- FR-03: Filter questions by subject, chapter, origin, and approval status.
- FR-04: Display a question and its options without exposing the answer prematurely in exam mode.
- FR-05: Provide immediate feedback in practice mode.
- FR-06: Calculate scores deterministically on the client or trusted backend, never by asking the LLM.
- FR-07: Save attempts and incorrect-question status locally.
- FR-08: Store source ID, edition, chapter, and page metadata for each textbook-grounded question.
- FR-09: Generate candidate questions using retrieved evidence.
- FR-10: Reject malformed or unsupported generated questions.
- FR-11: Make API keys backend-only.
- FR-12: Provide useful empty, loading, timeout, offline, and error states.
- FR-13: Support a question-bank export/import format for content review and versioning.
- FR-14: Distinguish `textbook`, `adapted`, and `ai_generated` question origins in the UI.

## 8. Non-functional requirements
- Reliability: saved, approved questions remain usable when the network or Groq is unavailable.
- Accuracy: no question is labelled verified until it passes the defined review gate.
- Performance: cached chapter questions should load promptly on a typical Android device; establish and measure a concrete target during implementation.
- Security: HTTPS in production, backend secrets, input validation, request limits, and minimal personal data.
- Accessibility: readable text, adequate contrast, scalable font sizes, screen-reader labels, and touch targets.
- Maintainability: modular retrieval, LLM provider adapter, schema validation, and migrations.
- Auditability: track source/version, model, prompt version, and review status for generated items.

## 9. Content and answer quality
A question can be marked `verified` only when:
- its source and textbook edition are known;
- its correct answer is supported by the cited source;
- options are valid and there is one unambiguous intended answer;
- its explanation does not contradict the source;
- it is not a duplicate or misleading paraphrase;
- review requirements for its origin are satisfied.

Extracted source text can contain OCR errors. A page reference alone does not prove correctness.

## 10. Success metrics
Measure these during pilot use:
- percentage of textbook pages successfully extracted and reviewed;
- retrieval relevance on a manually prepared evaluation set;
- percentage of generated candidates accepted after review;
- answer correctness and ambiguity rate from human audits;
- duplicate-question rate;
- completion rate for practice sessions;
- improvement in accuracy on repeated questions;
- crash rate and offline quiz success rate.

Do not use the volume of generated questions as the sole success metric.

## 11. Risks and mitigations
- Hallucinations: evidence-bound prompts, schema checks, source validation, human review.
- Poor PDF extraction: OCR, page-image spot checks, extraction quality reports.
- Wrong textbook edition: source registry and edition filters.
- Retrieval misses: evaluate chunking, metadata filters, embeddings, and keyword/hybrid search.
- LLM/API downtime or rate limits: pre-generated bank, caching, retries with limits, graceful failure.
- Copyright restrictions: source provenance, license review, avoid unauthorized redistribution.
- API key leakage: keep credentials only on backend.
- Syllabus changes: version textbook metadata and avoid mixing editions.

## 12. MVP acceptance criteria
- App launches on a supported Android device.
- All five subject areas can be opened.
- A sample chapter can be practised and scored correctly.
- Incorrect questions can be reviewed later.
- Approved questions display source information.
- RAG retrieves relevant passages for a tested set of chapter questions.
- Generated output is schema-validated and unsupported candidates are not published as verified.
- The app can run an existing quiz without Groq connectivity.
- No secrets are committed and setup instructions work on a clean development environment.
