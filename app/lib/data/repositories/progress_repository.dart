// lib/data/repositories/progress_repository.dart
// Local-only student progress — no server sync in MVP.

import 'package:uuid/uuid.dart';

import '../models/progress.dart';
import '../models/subject.dart';
import '../../core/networking/api_client.dart';
import '../../core/storage/local_database.dart';

class ProgressRepository {
  final LocalDatabase localDb;
  static const _uuid = Uuid();

  ProgressRepository({required this.localDb});

  Future<String> recordAttempt({
    required String localStudentId,
    required String questionId,
    String? subjectId,
    String? chapterId,
    String? selectedOptionId,
    required bool isCorrect,
    required String mode,
    int questionContentVersion = 1,
  }) async {
    assert(
      ['practice', 'exam', 'mistake_review'].contains(mode),
      'Invalid mode: $mode',
    );
    final db = await localDb.db;
    final attemptId = _uuid.v4();
    await db.insert('student_attempts', {
      'attempt_id': attemptId,
      'local_student_id': localStudentId,
      'question_id': questionId,
      'subject_id': subjectId,
      'chapter_id': chapterId,
      'selected_option_id': selectedOptionId,
      'is_correct': isCorrect ? 1 : 0,
      'mode': mode,
      'attempted_at': DateTime.now().toIso8601String(),
      'question_content_version': questionContentVersion,
    });
    return attemptId;
  }

  /// Questions answered incorrectly on their most recent attempt.
  Future<List<String>> getIncorrectQuestionIds(String localStudentId) async {
    final db = await localDb.db;
    final rows = await db.rawQuery('''
      SELECT a.question_id
      FROM student_attempts a
      INNER JOIN (
        SELECT question_id, MAX(attempted_at) as max_time
        FROM student_attempts
        WHERE local_student_id = ?
        GROUP BY question_id
      ) latest ON a.question_id = latest.question_id AND a.attempted_at = latest.max_time
      WHERE a.local_student_id = ? AND a.is_correct = 0
      ORDER BY a.attempted_at DESC
    ''', [localStudentId, localStudentId]);
    return rows.map((r) => r['question_id'] as String).toList();
  }

  /// Total count of currently unresolved mistakes.
  Future<int> getActiveMistakeCount(String localStudentId) async {
    final ids = await getIncorrectQuestionIds(localStudentId);
    return ids.length;
  }

  /// Mark an active mistake as resolved by recording a successful attempt.
  Future<void> resolveMistake({
    required String localStudentId,
    required String questionId,
  }) async {
    await recordAttempt(
      localStudentId: localStudentId,
      questionId: questionId,
      selectedOptionId: null,
      isCorrect: true,
      mode: 'mistake_review',
    );
  }

  /// Clear all unresolved mistakes for [localStudentId].
  Future<void> clearAllMistakes(String localStudentId) async {
    final ids = await getIncorrectQuestionIds(localStudentId);
    for (final id in ids) {
      await resolveMistake(
        localStudentId: localStudentId,
        questionId: id,
      );
    }
  }

  /// Reset all study attempts and records for [localStudentId].
  Future<void> resetAllRecords(String localStudentId) async {
    final db = await localDb.db;
    await db.delete(
      'student_attempts',
      where: 'local_student_id = ?',
      whereArgs: [localStudentId],
    );
  }

  Future<List<ChapterStats>> getChapterStats(
    String localStudentId, {
    String? subjectId,
  }) async {
    final db = await localDb.db;
    // Simplified: join not possible without chapter table; use attempt data directly
    final rows = await db.rawQuery('''
      SELECT
        SUBSTR(question_id, 1, 50) AS chapter_id,
        'unknown' AS subject_id,
        COUNT(*) AS total_attempts,
        SUM(is_correct) AS correct_count
      FROM student_attempts
      WHERE local_student_id = ?
      GROUP BY question_id
    ''', [localStudentId]);
    return rows
        .map((r) => ChapterStats.fromMap({
              'chapter_id': r['chapter_id'],
              'subject_id': r['subject_id'],
              'total_attempts': r['total_attempts'],
              'correct_count': r['correct_count'],
            }))
        .toList();
  }

  Future<Map<String, int>> getOverallStats(String localStudentId) async {
    final db = await localDb.db;
    final row = await db.rawQuery('''
      SELECT COUNT(*) AS total, SUM(is_correct) AS correct
      FROM student_attempts WHERE local_student_id = ?
    ''', [localStudentId]);
    if (row.isEmpty) return {'total': 0, 'correct': 0};
    return {
      'total': (row.first['total'] as int?) ?? 0,
      'correct': (row.first['correct'] as int?) ?? 0,
    };
  }

  /// Returns complete subject & chapter mastery insights for all 5 subjects
  Future<List<SubjectMastery>> getSubjectAndChapterMastery(
    String localStudentId, {
    ApiClient? api,
  }) async {
    final db = await localDb.db;

    // Dynamically verify column presence in student_attempts
    bool hasSubjectCol = false;
    bool hasChapterCol = false;
    try {
      final info = await db.rawQuery("PRAGMA table_info(student_attempts)");
      final cols = info
          .map((r) => (r['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet();
      hasSubjectCol = cols.contains('subject_id');
      hasChapterCol = cols.contains('chapter_id');

      if (!hasSubjectCol) {
        await db.execute('ALTER TABLE student_attempts ADD COLUMN subject_id TEXT');
        hasSubjectCol = true;
      }
      if (!hasChapterCol) {
        await db.execute('ALTER TABLE student_attempts ADD COLUMN chapter_id TEXT');
        hasChapterCol = true;
      }
    } catch (_) {}

    final subExpr = hasSubjectCol
        ? "COALESCE(NULLIF(a.subject_id, ''), q.subject_id, 'unknown')"
        : "COALESCE(q.subject_id, 'unknown')";
    final chExpr = hasChapterCol
        ? "COALESCE(NULLIF(a.chapter_id, ''), q.chapter_id, 'unknown')"
        : "COALESCE(q.chapter_id, 'unknown')";

    // 1. Query attempt metrics grouped by subject and chapter
    final attemptRows = await db.rawQuery('''
      SELECT
        $subExpr AS sub_id,
        $chExpr AS ch_id,
        COUNT(*) AS total_attempts,
        SUM(a.is_correct) AS correct_count,
        MAX(a.attempted_at) AS last_attempted_at
      FROM student_attempts a
      LEFT JOIN cached_questions q ON a.question_id = q.question_id
      WHERE a.local_student_id = ?
      GROUP BY 1, 2
    ''', [localStudentId]);

    // 2. Query active unresolved mistakes per subject & chapter
    final mistakeRows = await db.rawQuery('''
      SELECT
        $subExpr AS sub_id,
        $chExpr AS ch_id,
        COUNT(DISTINCT a.question_id) AS active_mistakes
      FROM student_attempts a
      INNER JOIN (
        SELECT question_id, MAX(attempted_at) as max_time
        FROM student_attempts
        WHERE local_student_id = ?
        GROUP BY question_id
      ) latest ON a.question_id = latest.question_id AND a.attempted_at = latest.max_time
      LEFT JOIN cached_questions q ON a.question_id = q.question_id
      WHERE a.local_student_id = ? AND a.is_correct = 0
      GROUP BY 1, 2
    ''', [localStudentId, localStudentId]);

    final Map<String, int> attemptCountMap = {};
    final Map<String, int> correctCountMap = {};
    final Map<String, DateTime?> lastAttemptMap = {};

    for (final r in attemptRows) {
      final sub = (r['sub_id'] as String? ?? 'unknown').trim().toLowerCase();
      final ch = (r['ch_id'] as String? ?? 'unknown').trim();
      final key = '$sub::$ch';
      attemptCountMap[key] = (r['total_attempts'] as num?)?.toInt() ?? 0;
      correctCountMap[key] = (r['correct_count'] as num?)?.toInt() ?? 0;
      final dtStr = r['last_attempted_at'] as String?;
      if (dtStr != null) {
        lastAttemptMap[key] = DateTime.tryParse(dtStr);
      }
    }

    final Map<String, int> mistakeCountMap = {};
    for (final r in mistakeRows) {
      final sub = (r['sub_id'] as String? ?? 'unknown').trim().toLowerCase();
      final ch = (r['ch_id'] as String? ?? 'unknown').trim();
      final key = '$sub::$ch';
      mistakeCountMap[key] = (r['active_mistakes'] as num?)?.toInt() ?? 0;
    }

    // 3. Collect chapters for all 5 subjects
    const subjects = ['tamil', 'english', 'mathematics', 'science', 'social_science'];
    final List<SubjectMastery> result = [];

    for (final subId in subjects) {
      List<Chapter> chapters = CanonicalSyllabus.getChapters(subId);
      if (api != null) {
        try {
          final remoteChapters = await api.fetchChapters(subId);
          if (remoteChapters.isNotEmpty) {
            final remoteIds = remoteChapters.map((c) => c.chapterId).toSet();
            final merged = List<Chapter>.from(remoteChapters);
            for (final c in chapters) {
              if (!remoteIds.contains(c.chapterId)) {
                merged.add(c);
              }
            }
            merged.sort((a, b) => a.chapterNumber.compareTo(b.chapterNumber));
            chapters = merged;
          }
        } catch (_) {}
      }

      final chapterMasteryList = chapters.map((ch) {
        final key = '$subId::${ch.chapterId}';
        final total = attemptCountMap[key] ?? 0;
        final correct = correctCountMap[key] ?? 0;
        final mistakes = mistakeCountMap[key] ?? 0;
        final lastAt = lastAttemptMap[key];

        return ChapterMastery(
          chapterId: ch.chapterId,
          chapterTitle: ch.title,
          chapterNumber: ch.chapterNumber,
          subjectId: subId,
          totalAttempts: total,
          correctAttempts: correct,
          activeMistakes: mistakes,
          lastAttemptedAt: lastAt,
        );
      }).toList();

      result.add(SubjectMastery(
        subjectId: subId,
        displayName: Subject.getDisplayName(subId),
        chapters: chapterMasteryList,
      ));
    }

    return result;
  }
}
