// lib/data/models/progress.dart
// Local student progress & chapter mastery — privacy-first, no personal data

import 'package:flutter/material.dart';

class StudentAttempt {
  final String attemptId;
  final String localStudentId;
  final String questionId;
  final String? subjectId;
  final String? chapterId;
  final String? selectedOptionId;
  final bool isCorrect;
  final String mode; // 'practice' | 'exam' | 'mistake_review'
  final DateTime attemptedAt;
  final int questionContentVersion;

  const StudentAttempt({
    required this.attemptId,
    required this.localStudentId,
    required this.questionId,
    this.subjectId,
    this.chapterId,
    this.selectedOptionId,
    required this.isCorrect,
    required this.mode,
    required this.attemptedAt,
    required this.questionContentVersion,
  });

  Map<String, dynamic> toJson() => {
        'attempt_id': attemptId,
        'local_student_id': localStudentId,
        'question_id': questionId,
        'subject_id': subjectId,
        'chapter_id': chapterId,
        'selected_option_id': selectedOptionId,
        'is_correct': isCorrect ? 1 : 0,
        'mode': mode,
        'attempted_at': attemptedAt.toIso8601String(),
        'question_content_version': questionContentVersion,
      };

  factory StudentAttempt.fromMap(Map<String, dynamic> map) => StudentAttempt(
        attemptId: map['attempt_id'] as String,
        localStudentId: map['local_student_id'] as String,
        questionId: map['question_id'] as String,
        subjectId: map['subject_id'] as String?,
        chapterId: map['chapter_id'] as String?,
        selectedOptionId: map['selected_option_id'] as String?,
        isCorrect: (map['is_correct'] as int) == 1,
        mode: map['mode'] as String,
        attemptedAt: DateTime.parse(map['attempted_at'] as String),
        questionContentVersion: (map['question_content_version'] ?? 1) as int,
      );
}

class ChapterStats {
  final String chapterId;
  final String subjectId;
  final int totalAttempts;
  final int correctCount;

  const ChapterStats({
    required this.chapterId,
    required this.subjectId,
    required this.totalAttempts,
    required this.correctCount,
  });

  double get accuracy => totalAttempts == 0 ? 0 : correctCount / totalAttempts;

  factory ChapterStats.fromMap(Map<String, dynamic> map) => ChapterStats(
        chapterId: map['chapter_id'] as String,
        subjectId: map['subject_id'] as String,
        totalAttempts: map['total_attempts'] as int,
        correctCount: map['correct_count'] as int,
      );
}

enum MasteryLevel {
  notStarted,
  needsPractice,
  proficient,
  mastered,
}

extension MasteryLevelExt on MasteryLevel {
  String get label {
    switch (this) {
      case MasteryLevel.notStarted:
        return 'Not Started';
      case MasteryLevel.needsPractice:
        return 'Needs Practice';
      case MasteryLevel.proficient:
        return 'Proficient';
      case MasteryLevel.mastered:
        return 'Mastered';
    }
  }

  Color get color {
    switch (this) {
      case MasteryLevel.notStarted:
        return const Color(0xFF64748B);
      case MasteryLevel.needsPractice:
        return const Color(0xFFEA580C);
      case MasteryLevel.proficient:
        return const Color(0xFF2563EB);
      case MasteryLevel.mastered:
        return const Color(0xFF059669);
    }
  }

  Color get bgColor {
    switch (this) {
      case MasteryLevel.notStarted:
        return const Color(0xFFF1F5F9);
      case MasteryLevel.needsPractice:
        return const Color(0xFFFFF7ED);
      case MasteryLevel.proficient:
        return const Color(0xFFEFF6FF);
      case MasteryLevel.mastered:
        return const Color(0xFFECFDF5);
    }
  }

  Color get borderColor {
    switch (this) {
      case MasteryLevel.notStarted:
        return const Color(0xFFCBD5E1);
      case MasteryLevel.needsPractice:
        return const Color(0xFFFED7AA);
      case MasteryLevel.proficient:
        return const Color(0xFFBFDBFE);
      case MasteryLevel.mastered:
        return const Color(0xFFA7F3D0);
    }
  }

  IconData get icon {
    switch (this) {
      case MasteryLevel.notStarted:
        return Icons.radio_button_unchecked_rounded;
      case MasteryLevel.needsPractice:
        return Icons.error_outline_rounded;
      case MasteryLevel.proficient:
        return Icons.trending_up_rounded;
      case MasteryLevel.mastered:
        return Icons.verified_rounded;
    }
  }
}

class ChapterMastery {
  final String chapterId;
  final String chapterTitle;
  final int chapterNumber;
  final String subjectId;
  final int totalAttempts;
  final int correctAttempts;
  final int activeMistakes;
  final DateTime? lastAttemptedAt;

  const ChapterMastery({
    required this.chapterId,
    required this.chapterTitle,
    required this.chapterNumber,
    required this.subjectId,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    this.activeMistakes = 0,
    this.lastAttemptedAt,
  });

  int get incorrectAttempts => totalAttempts - correctAttempts;

  double get accuracy => totalAttempts == 0 ? 0.0 : correctAttempts / totalAttempts;

  bool get isMastered => masteryLevel == MasteryLevel.mastered;

  MasteryLevel get masteryLevel {
    if (totalAttempts == 0) return MasteryLevel.notStarted;
    if (totalAttempts >= 5 && accuracy >= 0.85 && activeMistakes == 0) {
      return MasteryLevel.mastered;
    }
    if (totalAttempts >= 3 && accuracy >= 0.70 && activeMistakes == 0) {
      return MasteryLevel.proficient;
    }
    return MasteryLevel.needsPractice;
  }
}

class SubjectMastery {
  final String subjectId;
  final String displayName;
  final List<ChapterMastery> chapters;

  const SubjectMastery({
    required this.subjectId,
    required this.displayName,
    required this.chapters,
  });

  int get totalChapters => chapters.length;

  int get attemptedChapters =>
      chapters.where((c) => c.totalAttempts > 0).length;

  int get masteredChapters =>
      chapters.where((c) => c.masteryLevel == MasteryLevel.mastered).length;

  int get proficientChapters =>
      chapters.where((c) => c.masteryLevel == MasteryLevel.proficient).length;

  int get needsPracticeChapters =>
      chapters.where((c) => c.masteryLevel == MasteryLevel.needsPractice).length;

  int get notStartedChapters =>
      chapters.where((c) => c.masteryLevel == MasteryLevel.notStarted).length;

  int get totalAttempts =>
      chapters.fold(0, (sum, c) => sum + c.totalAttempts);

  int get totalCorrect =>
      chapters.fold(0, (sum, c) => sum + c.correctAttempts);

  int get activeMistakes =>
      chapters.fold(0, (sum, c) => sum + c.activeMistakes);

  double get overallAccuracy =>
      totalAttempts == 0 ? 0.0 : totalCorrect / totalAttempts;

  double get coveragePercent =>
      totalChapters == 0 ? 0.0 : attemptedChapters / totalChapters;

  ChapterMastery? get strongestChapter {
    final attempted = chapters.where((c) => c.totalAttempts >= 3).toList();
    if (attempted.isEmpty) return null;
    attempted.sort((a, b) => b.accuracy.compareTo(a.accuracy));
    return attempted.first;
  }

  ChapterMastery? get weakestChapter {
    final needsWork = chapters
        .where((c) => c.masteryLevel == MasteryLevel.needsPractice)
        .toList();
    if (needsWork.isNotEmpty) {
      needsWork.sort((a, b) {
        final mistakeDiff = b.activeMistakes.compareTo(a.activeMistakes);
        if (mistakeDiff != 0) return mistakeDiff;
        return a.accuracy.compareTo(b.accuracy);
      });
      return needsWork.first;
    }
    return null;
  }
}
