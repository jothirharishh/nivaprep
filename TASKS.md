# Implementation Checklist — BoardMate 10

Status key: `[ ]` not started, `[x]` complete, `[!]` blocked/needs decision. Update this file as work is completed. Do not mark a task complete without checking its acceptance criteria.

## Phase 0 — Project setup
- [x] Confirm repository root and Flutter project location.
- [x] Install Flutter, Android SDK, Python, and Git.
- [x] Run `flutter doctor` and resolve Android toolchain issues.
- [x] Create Flutter app and confirm it launches on emulator/device.
- [x] Create backend virtual environment and pin Python dependencies.
- [x] Add `.gitignore` for `.env`, raw textbooks, generated indexes, local DBs, caches, and build artifacts.
- [x] Add `.env.example` with placeholder values only.
- [x] Confirm source textbook edition, medium, year, and rights/usage terms.

**Exit criteria:** a clean Flutter starter launches, backend health endpoint runs, and secrets/private source files are excluded from Git. (COMPLETED)

## Phase 1 — Define content and schemas
- [x] Implement source registry schema.
- [x] Implement passage/chunk schema with page and chapter metadata.
- [x] Implement question schema and lifecycle states.
- [x] Define subject IDs and textbook-edition IDs.
- [x] Define question origin labels: textbook, adapted, AI-generated.
- [x] Define import/export format for question review.
- [x] Add synthetic fixtures for tests.

**Exit criteria:** schemas are documented and validated, and sample records pass automated tests. (COMPLETED)

## Phase 2 — Textbook ingestion
- [x] Build PDF page-text extraction.
- [x] Detect empty or low-text pages that may need OCR.
- [x] Preserve page numbers and source IDs.
- [x] Implement chapter segmentation or a reviewed chapter map.
- [x] Implement chunking with overlap where useful.
- [x] Store extraction quality and OCR method.
- [x] Produce an ingestion report for missing/empty pages.
- [x] Manually compare extracted text against sample page images.
- [x] Build a repeatable index-generation script.

**Exit criteria:** one selected chapter has usable, page-linked chunks and an ingestion report with known issues. (COMPLETED — All 5 subjects ingested: 8,398 chunks)

## Phase 3 — Retrieval evaluation
- [x] Implement embedding adapter.
- [x] Build FAISS index for the prototype.
- [x] Apply subject, edition, chapter, and page filters.
- [x] Add keyword fallback or hybrid retrieval if semantic search misses exact facts.
- [x] Create a small manually labelled retrieval test set.
- [x] Measure whether relevant passages appear in top-k results.
- [x] Tune chunk size, overlap, and top-k based on evaluation.

**Exit criteria:** retrieval returns useful, correctly scoped passages for the evaluation questions. (COMPLETED)

## Phase 4 — Groq integration
- [x] Implement Groq provider adapter.
- [x] Read API key and model ID from environment variables.
- [x] Add timeouts, bounded retries, and rate-limit handling.
- [x] Define prompts for MCQ generation and textbook Q&A with subject-specific exam patterns (question.md and tamil.md).
- [x] Require structured JSON output where supported.
- [x] Validate output with a strict schema.
- [x] Reject unknown source IDs and invalid answer indexes.
- [x] Check duplicate options and duplicate/near-duplicate questions (multi-level deduplication).
- [x] Require evidence and abstention when evidence is insufficient.
- [x] Add mocked tests that do not call Groq.

**Exit criteria:** malformed or unsupported model output is rejected safely, and the backend works with mocked LLM responses. (COMPLETED)

## Phase 5 — Question review and bank
- [x] Add pending-review workflow.
- [x] Show question, options, answer, explanation, and source passages to reviewer.
- [x] Allow approve, edit, reject, and retire actions.
- [x] Store reviewer status and timestamps.
- [x] Publish only verified/live questions to normal practice endpoints.
- [x] Track model ID and prompt version for AI-generated candidates.
- [x] Audit a sample of approved questions independently.

**Exit criteria:** no unreviewed candidate appears in the verified bank. (COMPLETED)

## Phase 6 — Flutter practice UX
- [x] Build subject list.
- [x] Build chapter list from the confirmed edition (Canonical syllabus with 56 chapters).
- [x] Build question and option UI.
- [x] Implement practice mode with immediate feedback.
- [x] Implement exam mode with answers hidden until submission.
- [x] Build results and answer review.
- [x] Build mistake review with progressive drill-down.
- [x] Save attempts locally in SQLite.
- [x] Build Progress section with chapter and subject mastery insights.
- [x] Add loading, empty, offline, and error states (scrollable, non-overflowing).
- [x] Add scalable text, accessible labels, and touch-friendly controls.

**Exit criteria:** a student can complete a practice session and review mistakes without a network connection after content is cached. (COMPLETED)

## Phase 7 — API integration and sync
- [x] Implement API client and typed response models.
- [x] Add request timeout and retry policy appropriate to each endpoint.
- [x] Cache approved questions locally in SQLite.
- [x] Handle stale content versions.
- [x] Add optional progress sync only after privacy and authentication decisions.
- [x] Keep Groq credentials entirely on the backend.

**Exit criteria:** normal quizzes continue working when the API or Groq is unavailable. (COMPLETED)

## Phase 8 — Subject rollout
- [x] Verify Tamil subject content (7 Iyals aligned with tamil.md).
- [x] Verify English subject content (7 Units).
- [x] Verify Mathematics content and formula rendering (8 Chapters).
- [x] Verify Science content, diagrams, symbols, and units (23 Chapters).
- [x] Verify Social Science dates, names, maps, and facts (11 Units).
- [x] Track per-chapter extraction and review coverage.
- [x] Avoid claiming full coverage while chapters remain incomplete.

**Exit criteria:** each released chapter passes the same content-quality gate. (COMPLETED)

## Phase 9 — Release
- [x] Run automated tests (82 Pytest backend tests, 23 Flutter unit/widget tests).
- [x] Run static analysis and formatting (0 Flutter analyze issues, 0 lint warnings).
- [x] Test on at least one emulator and one physical device if available.
- [x] Test offline mode, app restart, low connectivity, and API failures.
- [x] Confirm no secrets or unauthorized textbook files are included.
- [x] Build release APK/AAB readiness.
- [x] Document supported Android versions and known limitations.
- [x] Back up question bank and release artifacts.

**Exit criteria:** all release gates in `TESTING.md` pass. (COMPLETED)
