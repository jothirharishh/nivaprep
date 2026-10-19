# Architecture — BoardMate 10

## 1. Design overview
Use a modular client/server architecture. Flutter handles the study experience and local practice state. Flask provides content and RAG endpoints. Groq is accessed only by the backend. A verified question bank serves normal quizzes; LLM generation is an authoring workflow, not a dependency for every question displayed.

## 2. Logical components

```text
Flutter Android App
  ├── Subject / Chapter UI
  ├── Practice Quiz and Results
  ├── Mistake Review
  ├── Local Cache and Progress
  └── API Client
          |
          | HTTPS in production
          v
Flask API
  ├── Question Bank Service
  ├── Progress Service
  ├── Textbook Q&A Service
  ├── Generation / Admin Service
  └── Validation and Rate Limiting
          |
          +--> SQLite / production database
          |
          +--> RAG Service
          |      ├── Query filters
          |      ├── Retriever
          |      ├── Vector index (FAISS prototype)
          |      └── Source passage metadata
          |
          +--> Groq Provider Adapter
                    └── Groq API

Offline ingestion / authoring pipeline
  ├── Source registry and rights notes
  ├── PDF text extraction / OCR
  ├── Page and chapter segmentation
  ├── Chunking with metadata
  ├── Embedding and index building
  ├── Candidate question generation
  ├── Deterministic validation / duplicate checks
  └── Human review and publish
```

## 3. Key architectural decisions

### 3.1 Pre-generated bank for practice
Normal practice reads approved question records. It does not call Groq for every answer. This improves consistency, latency, cost control, and offline support.

### 3.2 RAG for grounding and coverage
RAG supplies passages relevant to a selected subject, edition, chapter, and query. It reduces reliance on model memory but does not prove the generated answer is correct.

### 3.3 Modular LLM provider
Keep Groq-specific API calls behind a provider interface. Model names and generation settings are configuration, not hard-coded assumptions. Verify current Groq model availability before deployment.

### 3.4 Separate content lifecycle
Candidate questions are not automatically approved questions. Use explicit states such as `draft`, `pending_review`, `verified`, `rejected`, and `retired`.

### 3.5 Start simple
Use FAISS and SQLite for the prototype. Abstract retrieval and persistence interfaces so the project can move to a managed vector store or production database if scale requires it.

## 4. Data flow: textbook ingestion
1. Register the source: subject, medium, edition, year, publisher, rights/permission notes, checksum.
2. Extract page-level text with PyMuPDF.
3. Detect whether OCR is needed. OCR scanned pages and record the method.
4. Review page text and chapter boundaries.
5. Split content into semantically coherent chunks.
6. Attach source, page, chapter, language, and extraction-quality metadata.
7. Create embeddings and build/update the index.
8. Run ingestion checks and report missing pages, empty pages, and likely OCR problems.

## 5. Data flow: candidate question generation
1. Maintainer selects subject, book edition, chapter, question type, and target count.
2. Retrieve a small set of relevant chunks, filtered to the selected scope.
3. Send the retrieved evidence and strict output schema to Groq.
4. Require the model to return question text, options, answer, explanation, and source chunk IDs.
5. Parse the JSON and validate types, counts, answer index, duplicates, and source IDs.
6. Check whether the cited evidence supports the answer. Flag uncertainty rather than assuming correctness.
7. Save as pending review.
8. Human reviewer approves, edits, or rejects.
9. Only verified questions are included in the verified bank.

## 6. Data flow: student practice
1. App requests questions for subject/chapter/mode.
2. API returns approved records or app uses its local cache.
3. Student selects an option.
4. Scoring is deterministic.
5. App reveals the answer/explanation at the appropriate time.
6. Attempt and mistake state are saved locally and synced only if/when a sync feature exists.

## 7. Data flow: textbook Q&A
1. Receive question and optional subject/chapter scope.
2. Validate request and apply retrieval filters.
3. Retrieve relevant chunks; optionally rerank them.
4. If evidence is insufficient, return an abstention response.
5. Generate an answer constrained to retrieved evidence.
6. Validate source IDs and return answer with page references.
7. Log latency, retrieval IDs, model/config version, and error class without logging unnecessary student personal data.

## 8. Suggested backend modules

```text
backend/
  app.py
  config.py
  api/
    questions.py
    practice.py
    textbook_qa.py
    admin_generation.py
  ingestion/
    pdf_extract.py
    chapter_segment.py
    chunk.py
    index.py
  rag/
    embeddings.py
    retriever.py
    prompts.py
    generator.py
    validation.py
  repositories/
    question_repository.py
    source_repository.py
    progress_repository.py
  models/
    question.py
    passage.py
    source.py
  tests/
```

## 9. Suggested Flutter modules

```text
app/lib/
  main.dart
  core/
    config/
    networking/
    storage/
  features/
    subjects/
    chapters/
    practice/
    results/
    mistakes/
    settings/
  data/
    models/
    repositories/
```

Use a state-management approach that the implementation can test easily. Avoid introducing a large framework before there is a clear need.

## 10. API outline
All paths are proposed contracts and may be refined during implementation.

- `GET /health` — service health, no secrets.
- `GET /v1/subjects` — supported subjects.
- `GET /v1/subjects/{subject_id}/chapters` — chapters for a selected edition.
- `GET /v1/questions` — approved questions filtered by subject, chapter, origin, and limit.
- `POST /v1/textbook/ask` — grounded textbook Q&A.
- `POST /v1/admin/generation-jobs` — create a candidate generation job; protect this endpoint.
- `GET /v1/admin/generation-jobs/{job_id}` — job status and validation report.
- `POST /v1/admin/questions/{question_id}/review` — approve, edit, reject, or retire; protect this endpoint.

Never expose admin generation/review routes to unauthenticated public use in production.

## 11. Reliability and security
- Set connection and read timeouts for Groq.
- Handle rate limits and transient errors with bounded retries.
- Avoid retry loops that increase cost.
- Apply input length and request-size limits.
- Validate all model output as untrusted data.
- Use HTTPS in production.
- Use backend secrets management and `.env` only for local development.
- Keep raw textbook files out of public web roots and source control.
- Keep logs free of API keys and unnecessary personal information.
- Back up the approved question bank and version ingestion/index artifacts.

## 12. Observability
Capture request ID, endpoint, duration, retrieval result IDs, model identifier, prompt version, validation outcome, and error category. Do not log secrets. Establish latency and cost baselines before optimizing.

## 13. Deployment stages
1. Local Flutter + local Flask + local FAISS/SQLite.
2. Private pilot with a small verified chapter bank.
3. Hosted API with HTTPS, secret management, backups, and rate limits.
4. Broader content rollout after subject-by-subject quality evaluation.
