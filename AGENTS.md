# AGENTS.md — BoardMate 10

## Mission
Build BoardMate 10, an Android study app for Tamil Nadu Samacheer Kalvi Class 10 students. The initial question language is English. The app helps students practise textbook-based one-mark questions, review mistakes, and track progress.

## Product principles
1. **Textbook fidelity over question volume.** Never present invented questions as original textbook questions.
2. **Evidence before confidence.** Every question in the verified bank must have a traceable source and a review status.
3. **Separate original and generated questions.** Label questions as `textbook`, `adapted`, or `ai_generated`.
4. **No unsupported answers.** If evidence is missing or ambiguous, do not mark a question as verified.
5. **Student-friendly UX.** Keep practice fast, readable, accessible, and free of unnecessary distractions.
6. **Privacy by default.** The first release should work without an account. Do not collect personal data unless required.
7. **Do not expose secrets.** Groq API keys and other credentials must only exist on the backend, never in Flutter code or a committed `.env` file.

## Stack and boundaries
- Android app: Flutter + Dart.
- API: Python + Flask.
- LLM provider: Groq API, using a currently supported model configured via environment variables.
- PDF text extraction: PyMuPDF; OCR may be added for scanned pages.
- Retrieval: embeddings + FAISS for the prototype; keep the retrieval interface replaceable.
- App/API metadata and progress: SQLite for the first backend prototype; choose a migration path before production.
- Keep textbook ingestion, retrieval, generation, validation, API, and UI in separate modules.

## Coding rules
- Prefer small, testable functions and explicit data models.
- Validate all API inputs and all model outputs.
- Use typed Dart models and Python type hints where practical.
- Do not couple UI widgets directly to database or LLM provider logic.
- Keep configuration in environment variables and provide `.env.example` with placeholders only.
- Add tests for parsing, chunking, retrieval filters, JSON validation, answer validation, scoring, and API errors.
- Use deterministic seeded examples in tests. Tests must not require a live Groq API.
- Handle network failures, timeouts, rate limits, malformed LLM responses, empty retrieval, and invalid source references.
- Never use an LLM response as executable code or as trusted configuration.
- Avoid silently changing a question's correct answer during editing. Log/review such changes.

## RAG and question-generation rules
- Filter retrieval by subject, book edition, medium, chapter, and page metadata whenever available.
- Return source passage IDs and page references with every generated question.
- Ask the model to abstain when the supplied evidence does not support a question or answer.
- Validate the response against a strict schema. Reject missing fields, invalid option counts, invalid answer indexes, duplicate options, and absent source IDs.
- A model-generated explanation is not proof of correctness. Verify the answer against the cited passage and route uncertain cases to human review.
- Never claim complete coverage of a textbook until ingestion and coverage checks confirm it.
- Do not fabricate page numbers, quotations, textbook editions, or citations.
- Avoid generating near-duplicates of existing questions.
- Store prompt/model/version metadata for generated items so results can be reproduced and audited.

## Content and copyright
- Use textbooks supplied by the user or obtained from sources whose terms permit the intended use.
- Keep provenance and licensing/permission notes for each source.
- Do not redistribute complete copyrighted textbooks or large verbatim extracts without permission.
- Store only the question text and excerpts necessary for the intended study use, subject to applicable rights and source terms.

## Definition of done
A feature is done when:
- acceptance criteria are met;
- relevant automated tests pass;
- loading, empty, and error states are handled;
- source/provenance requirements are met for content features;
- setup and configuration docs are updated;
- no secrets or private textbook files are committed;
- manual Android smoke testing is completed where applicable.
