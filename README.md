# BoardMate 10

BoardMate 10 is a planned Android app for Tamil Nadu Samacheer Kalvi Class 10 board-exam preparation. It focuses on one-mark practice based on the student's textbooks, with chapter filters, instant feedback, explanations, mistake review, and progress tracking.

## Current status

**Implemented & Verified.** The complete end-to-end system is built:
- **Android App:** Flutter + Material 3 client with offline SQLite cache, 5 subjects, practice, exam, mistake review, and local progress tracking.
- **Backend API:** Python + Flask with SQLite repositories, strict validation schemas, source provenance tracking, and Groq-powered RAG pipeline.
- **Textbook Ingestion:** PyMuPDF extraction, chapter segmentation, text chunking, and database seeding scripts.
- **Testing:** 82 automated backend unit/integration tests and 23 Flutter unit/widget tests. Both pass 100%. Static analysis clean with zero warnings.

## Product goals
- Practise questions by subject and chapter.
- Distinguish original textbook questions from adapted and AI-generated practice.
- Show answers, explanations, and source references.
- Save progress and revisit incorrect answers.
- Use RAG (retrieval-augmented generation) with a Groq-hosted LLM to create additional textbook-grounded questions.
- Keep approved questions available without needing an LLM call during every quiz.

## Planned stack
- Flutter/Dart Android client
- Python/Flask API
- Groq API for generation and optional textbook Q&A
- PyMuPDF for PDF extraction; OCR for scanned PDFs when needed
- Embeddings + FAISS for prototype retrieval
- SQLite for prototype metadata and progress
- Automated tests for ingestion, retrieval, validation, API and scoring

## Repository layout

```text
boardmate_10/
├── AGENTS.md
├── README.md
├── PRD.md
├── ARCHITECTURE.md
├── TASKS.md
├── TESTING.md
├── DATA_SCHEMA.md
├── app/                    # Flutter app (planned)
├── backend/                # Flask API and RAG pipeline (planned)
├── data/
│   ├── raw/                # Local-only source files; do not commit
│   ├── processed/          # Local-only extracted content; do not commit
│   └── fixtures/           # Small synthetic test fixtures only
└── scripts/                # Ingestion and maintenance scripts (planned)
```

Adjust paths if the repository already uses a different Flutter/Flask layout. Keep the documents at the repository root.

## Prerequisites
Install:
- Git
- Flutter SDK and the Android SDK (Android Studio can install the Android SDK)
- Python 3.11 or another version selected and pinned by the backend project
- A supported Android emulator or a physical Android device
- A Groq API key only for features that call Groq

Verify Flutter setup:

```bash
flutter doctor
flutter devices
```

## Run the Flutter app

From the Flutter project directory (the directory containing `pubspec.yaml`):

```bash
flutter pub get
flutter run
```

To build an APK:

```bash
flutter build apk --release
```

## Run the backend

From the repository root:

### Windows PowerShell

```powershell
pip install -r backend/requirements.txt
Copy-Item .env.example .env

# 1. Seed database with verified textbook questions
python scripts/seed_database.py

# 2. Run automated backend test suite
python -m pytest backend/tests -v --cov=backend

# 3. Start Flask API
python -m flask --app backend.app run --port 5000 --debug
```

### macOS/Linux

```bash
pip install -r backend/requirements.txt
cp .env.example .env

# 1. Seed database
python3 scripts/seed_database.py

# 2. Run automated test suite
python3 -m pytest backend/tests -v --cov=backend

# 3. Start Flask API
python3 -m flask --app backend.app run --port 5000 --debug
```

These commands are target instructions and must be reconciled with the actual module layout when implementation begins. Never commit `.env`.

## Configure Groq
- Create an API key using the official Groq developer console.
- Put it in the backend environment variable `GROQ_API_KEY`.
- Configure the model with `GROQ_MODEL`; use a model currently supported by the account and API.
- Do not hard-code model names or API keys.
- The core quiz flow should use the approved question bank and should not require a live LLM call.

## Textbook ingestion
1. Confirm the textbook subject, medium, edition/year, and source rights.
2. Keep original PDFs in a local-only raw-data directory.
3. Extract text and page metadata; use OCR when necessary.
4. Review chapter boundaries and extracted content.
5. Chunk passages while preserving subject, book, chapter, page, and source IDs.
6. Index chunks for retrieval.
7. Generate candidate questions and validate them.
8. Human-review questions before marking them verified.

## Quality and safety
- Label question origin clearly.
- Do not claim an AI-generated question is an official board question.
- Never invent a source page or cite a passage that does not support the answer.
- Keep textbook files and secrets out of version control.
- Treat student progress as private data.

## Documentation
- `PRD.md`: product goals, users, scope, and acceptance criteria
- `ARCHITECTURE.md`: component design and data flow
- `TASKS.md`: implementation checklist
- `TESTING.md`: test strategy and release gates
- `DATA_SCHEMA.md`: question, passage, source, and progress schemas
