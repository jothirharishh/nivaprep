// lib/data/repositories/question_repository.dart
// Manages question fetching: static bank (API + local cache) and live RAG generation.

import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../models/question.dart';
import '../../core/networking/api_client.dart';
import '../../core/storage/local_database.dart';

class QuestionRepository {
  final ApiClient api;
  final LocalDatabase localDb;

  QuestionRepository({required this.api, required this.localDb});

  // ── Static bank (pre-generated, human-reviewed) ──────────────────────────────

  Future<List<Question>> getQuestionsForChapter(
    String subjectId,
    String chapterId, {
    int limit = 50,
  }) async {
    try {
      final questions = await api.fetchQuestions(
        subjectId: subjectId,
        chapterId: chapterId,
        limit: limit,
      );
      // Cache for offline use
      await _cacheQuestions(questions);
      return questions;
    } on ApiException catch (e) {
      if (e.statusCode == null) {
        // Offline — try cache
        return _loadCached(subjectId, chapterId);
      }
      rethrow;
    }
  }

  Future<List<Question>> getCachedQuestionsForChapter(
    String subjectId,
    String chapterId,
  ) =>
      _loadCached(subjectId, chapterId);

  // ── Live RAG generation ──────────────────────────────────────────────────────

  /// Generate a single fresh question from the textbook via Groq RAG.
  /// Pass [alreadySeen] to avoid repeating questions in the same session.
  ///
  /// Throws [LiveGenerationUnavailableException] when the backend index is not
  /// built yet, or [ApiException] for other errors.
  Future<Question> generateLiveQuestion({
    required String subjectId,
    required String chapterId,
    List<String> alreadySeen = const [],
  }) async {
    final q = await api.generateLiveQuestion(
      subjectId: subjectId,
      chapterId: chapterId,
      excludeQuestionIds: alreadySeen,
    );
    // Cache live generated question so it is available offline, in mistake vault, and saved list
    await cacheQuestion(q);
    return q;
  }

  // ── Cache operations ─────────────────────────────────────────────────────────

  Future<void> cacheQuestion(Question question) => _cacheQuestions([question]);

  Future<void> cacheQuestions(List<Question> questions) => _cacheQuestions(questions);

  /// Load questions matching any of the specified [ids].
  Future<List<Question>> getQuestionsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final db = await localDb.db;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      'cached_questions',
      where: 'question_id IN ($placeholders)',
      whereArgs: ids,
    );
    final map = <String, Question>{};
    for (final r in rows) {
      final json = jsonDecode(r['data_json'] as String) as Map<String, dynamic>;
      final q = Question.fromJson(json);
      map[q.questionId] = q;
    }

    // Fallback: If any questions were not found in local cache, fetch from API
    for (final id in ids) {
      if (!map.containsKey(id)) {
        try {
          final q = await api.fetchQuestion(id);
          if (q != null) {
            map[id] = q;
            await cacheQuestion(q);
          }
        } catch (_) {}
      }
    }

    return ids.map((id) => map[id]).whereType<Question>().toList();
  }

  // ── Saved questions (Bookmarks) ──────────────────────────────────────────────

  /// Check whether a question has been saved/bookmarked by the student.
  Future<bool> isQuestionSaved(
    String questionId, {
    String studentId = 'local_anon',
  }) async {
    final db = await localDb.db;
    final rows = await db.query(
      'saved_questions',
      where: 'question_id = ? AND local_student_id = ?',
      whereArgs: [questionId, studentId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Toggle bookmark status for a question. Returns true if saved, false if unsaved.
  Future<bool> toggleSaveQuestion(
    Question question, {
    String studentId = 'local_anon',
  }) async {
    final db = await localDb.db;
    final isSaved = await isQuestionSaved(question.questionId, studentId: studentId);
    if (isSaved) {
      await db.delete(
        'saved_questions',
        where: 'question_id = ? AND local_student_id = ?',
        whereArgs: [question.questionId, studentId],
      );
      return false;
    } else {
      await cacheQuestion(question);
      await db.insert(
        'saved_questions',
        {
          'question_id': question.questionId,
          'local_student_id': studentId,
          'saved_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return true;
    }
  }

  /// Remove a question from the saved bookmarks list.
  Future<void> removeSavedQuestion(
    String questionId, {
    String studentId = 'local_anon',
  }) async {
    final db = await localDb.db;
    await db.delete(
      'saved_questions',
      where: 'question_id = ? AND local_student_id = ?',
      whereArgs: [questionId, studentId],
    );
  }

  /// Retrieve all bookmarked questions for [studentId], sorted most recent first.
  Future<List<Question>> getSavedQuestions({
    String studentId = 'local_anon',
  }) async {
    final db = await localDb.db;
    final rows = await db.query(
      'saved_questions',
      where: 'local_student_id = ?',
      whereArgs: [studentId],
      orderBy: 'saved_at DESC',
    );
    final ids = rows.map((r) => r['question_id'] as String).toList();
    return getQuestionsByIds(ids);
  }

  /// Count of saved questions for badge/counter display.
  Future<int> getSavedCount({
    String studentId = 'local_anon',
  }) async {
    final db = await localDb.db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM saved_questions WHERE local_student_id = ?',
      [studentId],
    );
    return (result.first['count'] as int?) ?? 0;
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<void> _cacheQuestions(List<Question> questions) async {
    if (questions.isEmpty) return;
    final db = await localDb.db;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert(
        'cached_questions',
        {
          'question_id': q.questionId,
          'subject_id': q.subjectId,
          'chapter_id': q.chapterId,
          'data_json': jsonEncode(q.toJson()),
          'cached_at': DateTime.now().toIso8601String(),
          'content_version': q.contentVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<Question>> _loadCached(
    String subjectId,
    String chapterId,
  ) async {
    final db = await localDb.db;
    final rows = await db.query(
      'cached_questions',
      where: 'subject_id = ? AND chapter_id = ?',
      whereArgs: [subjectId, chapterId],
    );
    return rows.map((r) {
      final json = jsonDecode(r['data_json'] as String) as Map<String, dynamic>;
      return Question.fromJson(json);
    }).toList();
  }
}
