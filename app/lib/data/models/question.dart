// lib/data/models/question.dart
// Typed Dart models mirroring backend DATA_SCHEMA.md

class QuestionOption {
  final String optionId;
  final String text;

  const QuestionOption({required this.optionId, required this.text});

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
      optionId: json['option_id'] as String, text: json['text'] as String);

  Map<String, dynamic> toJson() => {'option_id': optionId, 'text': text};
}

class SourceRef {
  final String passageId;
  final int? pdfPageIndex;
  final String printedPageLabel;
  final String? chapterTitle;

  const SourceRef({
    required this.passageId,
    this.pdfPageIndex,
    required this.printedPageLabel,
    this.chapterTitle,
  });

  factory SourceRef.fromJson(Map<String, dynamic> json) => SourceRef(
        passageId: json['passage_id'] as String,
        pdfPageIndex: json['pdf_page_index'] as int?,
        printedPageLabel: (json['printed_page_label'] ?? '').toString(),
        chapterTitle: json['chapter_title'] as String?,
      );
}

enum QuestionOrigin { textbook, adapted, aiGenerated }

extension QuestionOriginExt on QuestionOrigin {
  static QuestionOrigin fromString(String v) {
    switch (v) {
      case 'textbook':
        return QuestionOrigin.textbook;
      case 'adapted':
        return QuestionOrigin.adapted;
      default:
        return QuestionOrigin.aiGenerated;
    }
  }

  String get displayLabel {
    switch (this) {
      case QuestionOrigin.textbook:
        return 'Textbook Question';
      case QuestionOrigin.adapted:
        return 'Adapted Question';
      case QuestionOrigin.aiGenerated:
        return 'AI-Generated Practice';
    }
  }
}

class Question {
  final String questionId;
  final String subjectId;
  final String sourceId;
  final String chapterId;
  final String chapterTitle;
  final String language;
  final QuestionOrigin origin;
  final String questionText;
  final List<QuestionOption> options;
  final String correctOptionId;
  final String explanation;
  final List<SourceRef> sourceRefs;
  final String difficulty;
  final int contentVersion;

  const Question({
    required this.questionId,
    required this.subjectId,
    required this.sourceId,
    required this.chapterId,
    required this.chapterTitle,
    required this.language,
    required this.origin,
    required this.questionText,
    required this.options,
    required this.correctOptionId,
    required this.explanation,
    required this.sourceRefs,
    required this.difficulty,
    required this.contentVersion,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        questionId: json['question_id'] as String,
        subjectId: json['subject_id'] as String,
        sourceId: (json['source_id'] ?? '') as String,
        chapterId: json['chapter_id'] as String,
        chapterTitle: (json['chapter_title'] ?? '') as String,
        language: (json['language'] ?? 'en') as String,
        origin: QuestionOriginExt.fromString(json['origin'] as String),
        questionText: json['question_text'] as String,
        options: (json['options'] as List)
            .map((o) => QuestionOption.fromJson(o as Map<String, dynamic>))
            .toList(),
        correctOptionId: json['correct_option_id'] as String,
        explanation: (json['explanation'] ?? '') as String,
        sourceRefs: (json['source_refs'] as List? ?? [])
            .map((r) => SourceRef.fromJson(r as Map<String, dynamic>))
            .toList(),
        difficulty: (json['difficulty'] ?? 'unknown') as String,
        contentVersion: (json['content_version'] ?? 1) as int,
      );

  Map<String, dynamic> toJson() => {
        'question_id': questionId,
        'subject_id': subjectId,
        'source_id': sourceId,
        'chapter_id': chapterId,
        'chapter_title': chapterTitle,
        'language': language,
        'origin': origin.name,
        'question_text': questionText,
        'options': options.map((o) => o.toJson()).toList(),
        'correct_option_id': correctOptionId,
        'explanation': explanation,
        'difficulty': difficulty,
        'content_version': contentVersion,
      };
}
