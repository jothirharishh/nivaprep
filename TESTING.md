# Testing Strategy — BoardMate 10

## 1. Goals
Testing must verify app behaviour, retrieval relevance, answer correctness, provenance, and resilience to malformed or unavailable LLM responses. A successful API response or valid JSON is not proof that a question is correct.

## 2. Test layers

### Unit tests
Flutter:
- scoring and result calculation;
- question/option model parsing;
- practice/exam mode answer visibility;
- progress and mistake-review logic;
- cache serialization and version handling.

Backend:
- PDF page extraction and metadata;
- chapter segmentation and chunking;
- filter correctness;
- response-schema validation;
- answer-index and option validation;
- source-ID resolution;
- duplicate detection;
- repository CRUD;
- API input validation and error mapping.

### Integration tests
- PDF fixture → extraction → chunks → index.
- Query → retrieval → cited passages.
- Mock Groq response → validation → pending-review record.
- Approved question → API → Flutter quiz.
- Attempt → local persistence → app restart → mistake review.
- API unavailable → cached quiz remains usable.

### End-to-end tests
- Open app, choose subject/chapter, complete quiz, view score.
- Answer incorrectly and find the question in Mistake Review.
- Complete exam mode and confirm answers remain hidden until submission.
- Open cached content in airplane mode.
- Test large text settings and accessibility labels.

### Content quality tests
- Compare extracted pages against source page images.
- Confirm every verified question has a valid source and edition.
- Check answer is supported by the cited evidence.
- Check exactly one intended correct option.
- Check explanation does not contradict the source.
- Check for duplicate and near-duplicate questions.
- Check question wording does not introduce facts absent from the source unless explicitly labelled and reviewed.
- Audit each subject separately.

## 3. RAG evaluation
Create a manually reviewed set of representative questions for each tested chapter. Record expected relevant passage IDs.

Measure:
- **Recall@k:** whether a relevant passage appears in the top k results.
- **MRR or ranking quality:** whether relevant passages appear near the top.
- **Scope accuracy:** whether retrieval stays within the requested subject, edition, and chapter.
- **Citation validity:** whether returned passage IDs exist and point to the right page.
- **Abstention quality:** whether the system refuses to answer when the supplied evidence is insufficient.

Set numerical targets after creating a baseline. Do not claim good retrieval performance without measured results.

## 4. Question-generation evaluation
For a reviewed sample, score:
- factual correctness;
- evidence support;
- exactly one defensible correct answer;
- option quality and plausibility;
- explanation correctness;
- syllabus/chapter alignment;
- readability and age appropriateness;
- originality relative to the existing bank;
- valid source/page references.

Track acceptance rate after human review, not just generation success rate. Report results by subject and question type.

## 5. Required negative tests
- Empty retrieval result.
- Wrong chapter or edition filter.
- Corrupted/scanned PDF.
- OCR output with broken symbols or numbers.
- Groq timeout, 429/rate limit, 5xx, and unavailable model.
- Invalid JSON or truncated output.
- Missing options, fewer/more than four options, duplicate options.
- Answer index outside allowed range.
- Source ID that does not exist.
- Answer unsupported by the cited passage.
- Prompt injection text inside retrieved textbook content.
- Oversized request or malformed input.
- Offline device and empty local cache.
- Stale or incompatible cached question-bank version.

## 6. Security and privacy tests
- Confirm Groq key is absent from Flutter assets, logs, and source control.
- Confirm admin generation/review endpoints are protected.
- Confirm production traffic uses HTTPS.
- Confirm user input is validated and request size is bounded.
- Confirm logs do not contain credentials or unnecessary student data.
- Confirm raw textbooks and local databases are not accidentally packaged or committed.

## 7. Release criteria
A release candidate must satisfy all of the following:
- All critical automated tests pass.
- No known critical scoring or answer-reveal bugs.
- No question is labelled verified without source and review requirements.
- No known unsupported answer is present in the verified sample.
- Offline quiz works for cached/packaged approved questions.
- Main user journeys work on a supported Android device.
- Network, timeout, empty, and malformed-response states are handled.
- No secrets are committed.
- Setup instructions are tested on a clean environment.
- Known limitations are documented.

## 8. Reporting
For every test run, record commit/version, device or runtime, test command, pass/fail counts, and unresolved issues. For content audits, record the sample size, subject/chapter, reviewer, and issue categories. Do not present unmeasured estimates as test results.
