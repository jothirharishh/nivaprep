# BoardMate 10 — Flutter Android Client

BoardMate 10 is an Android study application designed specifically for Tamil Nadu Samacheer Kalvi Class 10 board exam preparation. It enables students to practise syllabus-grounded one-mark questions across all 5 subjects with immediate feedback, detailed pedagogical explanations, progressive mistake reviews, and chapter-level mastery tracking.

---

## Features

- **5 Class 10 Subjects:** Complete coverage across Tamil, English, Mathematics, Science, and Social Science.
- **56 Canonical Chapters:** Comprehensive syllabus view showing unattempted, practicing, and mastered chapters.
- **Multiple Practice Modes:**
  - **Immediate Practice:** Instant verification with rich 2-4 sentence explanations and verified textbook citations.
  - **Timed Exam Mode:** Delayed answer reveal with unanswered tally and final scoring.
  - **Mistake Review:** Progressive drill-down by subject and chapter allowing students to retry and resolve errors.
  - **Saved Questions:** Bookmark questions with notes for rapid pre-exam revision.
- **Diagnostic Progress & Insights:**
  - Overall board prep accuracy and chapters mastered gauge ($X / 56$).
  - Subject-by-subject filters with mastery counters.
  - Diagnostic spotlights highlighting the student's strongest chapter and revision priority chapter.
  - Search, filter by tier (`Needs Focus`, `Mastered`, `Not Started`), and direct "Practise" CTA actions.
- **Offline Resilience:** Local persistence in SQLite (`sqflite`), allowing quizzes, mistakes review, and scoring without internet connectivity.
- **Privacy by Default:** Operates without user accounts or external telemetry. All records remain on-device.

---

## Architecture & Modules

```text
app/lib/
├── core/
│   ├── config/          # Environment configuration (API endpoints)
│   ├── networking/      # ApiClient (HTTP calls, error mapping, timeouts)
│   ├── storage/         # LocalDatabase (SQLite schema, migrations, indexes)
│   ├── theme/           # Material 3 tokens, colors, typography
│   └── widgets/         # Common reusable UI components (OriginBadge, ErrorState, etc.)
├── data/
│   ├── models/          # Typed data models (Question, Subject, Chapter, Progress)
│   └── repositories/    # QuestionRepository, ProgressRepository
├── features/
│   ├── splash/          # Brand splash screen
│   ├── home/            # Home dashboard, subject list, quick revision
│   ├── subjects/        # Subject exploration and chapter selector
│   ├── practice/        # Practice quiz and timed exam session
│   ├── results/         # Session scoring and performance review
│   ├── mistakes/        # Mistake drill-down and interactive retry
│   ├── saved/           # Bookmarked questions manager
│   ├── progress/        # Chapter & subject mastery insights
│   └── settings/        # Provenance, local data reset, and app info
└── main.dart            # Application bootstrap & Provider hierarchy
```

---

## Development Setup

### Prerequisites
- Flutter SDK `>=3.0.0 <4.0.0`
- Android SDK (API 34+ recommended)

### Running Locally
```bash
# Get dependencies
flutter pub get

# Run on connected device or emulator
flutter run

# Run code analysis
flutter analyze

# Run automated tests
flutter test
```
