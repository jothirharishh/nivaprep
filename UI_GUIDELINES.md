# UI_GUIDELINES.md — BoardMate 10

## Purpose
Define the visual design, navigation, interaction patterns, and accessibility requirements for BoardMate 10, an Android app for Tamil Nadu Samacheer Kalvi Class 10 board-exam preparation. The initial question language is English.

## Product principles
- Textbook fidelity over question volume.
- Keep the interface calm, readable, encouraging, and focused on studying.
- Clearly distinguish textbook, adapted, and AI-generated questions.
- Show source references only when verified. Never fabricate page numbers or citations.
- Keep approved quizzes usable offline.
- Students should not need to understand RAG, embeddings, prompts, or Groq to use the app.
- Do not expose API keys or backend secrets in the Android app.

## Platform and design system
- Android first, built with Flutter and Material 3.
- Brand primary: `#3498DB`.
- Light background: `#F6F8FB`; card surface: `#FFFFFF`.
- Primary text: `#17212B`; secondary text: `#5E6B78`.
- Correct: `#218653`; incorrect: `#C0392B`; warning: `#9A6700`.
- Use a consistent 4/8-point spacing scale, 12–16dp card radius, and at least 48×48dp touch targets.
- Suggested type sizes: page title 26–30sp, section title 20–22sp, question 20–24sp, body/options 16–18sp, supporting text 14–16sp.
- Respect system font scaling. Do not rely on colour alone to convey correctness.
- Centralize theme tokens. Support light mode first and structure the theme so dark mode can be added later.

## Navigation
Recommended bottom navigation:
1. Home
2. Practice
3. Mistakes
4. Progress

Settings can be accessed from the Home app bar. No account is required for the MVP.

Navigation flow:
```text
Home
 ├── Continue Practice → Quiz
 ├── Daily Revision → Quiz
 ├── Subject → Chapter List → Mode Selection → Quiz
 ├── Mistakes → Review Quiz
 ├── Progress → Subject/Chapter Details
 └── Settings
```

## Required screens

### 1. Home
- Welcome message and clear “Start practice” or “Continue” action.
- Five subjects: Tamil, English, Mathematics, Science, Social Science.
- Daily revision and a small progress summary.
- Show real available-question counts only. If content is unavailable, say so instead of implying coverage.

### 2. Subject and chapter list
- Use chapter names from the confirmed textbook edition.
- Show approved question counts and progress status.
- Statuses may include Not started, In progress, Revised, and Content unavailable.
- Do not claim full chapter coverage unless ingestion and review records support it.

### 3. Chapter mode selection
Offer only modes that have content:
- Textbook Questions
- Verified Practice
- Mixed Practice
- Mistake Review, when applicable

Explain the selected textbook edition where useful. The student must still be able to practise approved questions if AI generation or the network is unavailable.

### 4. Practice quiz
- Show subject/chapter, question number, progress bar, question, and large answer options.
- Keep a single primary action: “Check answer”.
- Do not reveal the answer before checking.
- After checking, show correct/incorrect feedback, the correct answer, a concise explanation, and a verified source reference.
- Prevent double-scoring from repeated taps.
- Keep the question and options visible when feedback appears.

### 5. Exam mode
- Hide correctness and explanations until submission.
- Track unanswered questions.
- Reveal results and explanations after submission.
- A timer is optional; if present, handle pause/resume clearly.
- Calculate scores deterministically in code, never through an LLM.

### 6. Results
Show score, total, percentage, correct/incorrect/unanswered counts, and actions:
- Review answers
- Retry mistakes
- Practise another chapter
- Home

Avoid shaming language and never claim board-exam readiness from one short quiz.

### 7. Mistake review
- Group incorrect questions by subject and chapter.
- Show the selected answer, correct answer, explanation, and verified source.
- Let the student retry questions.
- Define clearly when a question leaves the active review list; preserve useful history.

### 8. Progress
Show questions attempted, accuracy, chapters started/revised, recent sessions, and questions due for review.
- Define the denominator for each percentage.
- Distinguish “not studied” from zero accuracy.
- Never display made-up progress or claim unsupported syllabus completion.

### 9. Textbook Q&A (future)
- Let the student select a subject/chapter scope and ask a question.
- Show an answer grounded in retrieved textbook passages and validated references.
- If evidence is insufficient, say so rather than inventing an answer or citation.
- Keep this secondary to the main quiz flow.

### 10. Settings
Include theme preference when supported, cache management if implemented, app version, content source/edition information, privacy notice, and a confirmation dialog before clearing local progress. Never place Groq credentials in settings.

## Content trust and provenance
Use unobtrusive origin labels:
- **Textbook question**: extracted from a source and reviewed.
- **Adapted question**: rewritten from textbook material, with source.
- **AI-generated practice**: generated from retrieved evidence and passed the review process.

Only show chapter/page references when verified. Do not label anything an official board question unless it actually comes from an official board paper. Do not expose a question as verified just because it is valid JSON or was generated by an LLM.

## Loading, empty, offline, and error states
Every data-dependent screen must handle:
- Loading state with a clear indicator.
- Empty chapter: “No verified questions available yet.”
- Offline: “You’re offline. You can continue with downloaded questions.”
- Network failure: “Couldn’t load new content. Try again or practise saved questions.”
- AI generation unavailable: existing approved questions remain usable.
- No mistakes: “You’re all caught up. Keep practising to build your review list.”
- No progress: “Your progress will appear after your first practice session.”

Offer a retry action when appropriate. Never use an infinite spinner or fabricate content to fill an empty screen.

## Accessibility
- Respect Android text scaling.
- Ensure readable contrast and screen-reader labels.
- Support TalkBack and keyboard/switch navigation where applicable.
- Do not use colour as the only signal for selection or correctness.
- Keep touch targets at least 48×48dp.
- Support long chapter titles, multi-line questions, and mathematical notation.
- Test narrow screens and common display/font scaling settings.
- Avoid flashing effects and distracting animations.

## Offline behaviour
- Cache or package approved question data.
- Keep scoring available offline.
- Save attempts locally.
- If syncing exists, show when content last synced and handle stale content versions.
- Never silently erase student history when question content changes.
- Never cache API credentials in the client.

## Flutter implementation guidance
- Use Material 3 and a centralized theme file.
- Build reusable widgets for subject cards, chapter rows, question progress, answer options, feedback panels, source labels, empty/offline/error states, and score summaries.
- Keep UI separate from repositories, networking, and local storage.
- Use typed models for questions, sources, attempts, and progress.
- Do not hard-code chapter lists; load versioned textbook metadata.
- Add widget tests for answer selection, checking, answer reveal, next question, results, and offline states.

Suggested folders:
```text
app/lib/
  core/theme/
  core/widgets/
  features/home/
  features/subjects/
  features/chapters/
  features/practice/
  features/results/
  features/mistakes/
  features/progress/
  features/textbook_qa/
  features/settings/
```

## MVP acceptance checklist
- [ ] Home displays all five subjects without fabricated counts.
- [ ] Chapter lists use the confirmed textbook edition.
- [ ] Unavailable content is clearly labelled.
- [ ] Practice mode reveals feedback only after checking.
- [ ] Exam mode hides feedback until submission.
- [ ] Scores and percentages are correct.
- [ ] Mistake Review shows incorrectly answered questions.
- [ ] Source labels reflect verified metadata.
- [ ] Cached quizzes work offline.
- [ ] Loading, empty, offline, and error states exist.
- [ ] Text scaling and TalkBack have been tested.
- [ ] RAG/LLM internals are not unnecessarily exposed to students.
- [ ] No secrets are included in the Flutter app.
