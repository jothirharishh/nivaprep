// lib/core/networking/api_client.dart
// HTTP client for the BoardMate backend API.
// Groq credentials are NEVER stored here.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../data/models/question.dart';
import '../../data/models/subject.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException(status=$statusCode): $message';
}

/// Thrown when the backend is not ready for live generation
/// (FAISS index not built, Groq key missing, etc.).
class LiveGenerationUnavailableException extends ApiException {
  const LiveGenerationUnavailableException(super.message)
      : super(statusCode: 503);
}

class ApiClient {
  final String baseUrl;
  final Duration timeout;
  final http.Client _http;

  ApiClient({
    required this.baseUrl,
    this.timeout = const Duration(seconds: 15),
    http.Client? client,
  }) : _http = client ?? http.Client();

  // ── Health ──────────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      final resp = await _get('/health');
      return resp['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ── Subjects ────────────────────────────────────────────────────────────────

  Future<List<Subject>> fetchSubjects() async {
    final data = await _get('/v1/subjects');
    final list = data['subjects'] as List;
    return list
        .map((s) => Subject.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  // ── Chapters ────────────────────────────────────────────────────────────────

  Future<List<Chapter>> fetchChapters(String subjectId) async {
    final data = await _get('/v1/subjects/$subjectId/chapters');
    final list = data['chapters'] as List;
    return list
        .map((c) => Chapter.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  // ── Questions (static bank) ──────────────────────────────────────────────────

  Future<List<Question>> fetchQuestions({
    String? subjectId,
    String? chapterId,
    String? origin,
    int limit = 50,
  }) async {
    final params = <String, String>{
      if (subjectId != null) 'subject_id': subjectId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (origin != null) 'origin': origin,
      'limit': limit.toString(),
    };
    final data = await _get('/v1/questions', queryParams: params);
    final list = data['questions'] as List;
    return list
        .map((q) => Question.fromJson(q as Map<String, dynamic>))
        .toList();
  }

  Future<Question?> fetchQuestion(String questionId) async {
    try {
      final data = await _get('/v1/questions/$questionId');
      return Question.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  // ── Live RAG generation ──────────────────────────────────────────────────────

  /// Generate a fresh MCQ question on-demand via the RAG pipeline.
  /// [excludeQuestionIds] prevents repeating questions already seen in session.
  /// Throws [LiveGenerationUnavailableException] when backend is not ready.
  Future<Question> generateLiveQuestion({
    required String subjectId,
    required String chapterId,
    List<String> excludeQuestionIds = const [],
  }) async {
    final data = await _post(
      '/v1/questions/generate',
      body: {
        'subject_id': subjectId,
        'chapter_id': chapterId,
        'exclude_question_ids': excludeQuestionIds,
      },
      // Groq + embedding can take up to 30 s
      customTimeout: const Duration(seconds: 35),
    );

    if (data['abstained'] == true) {
      throw ApiException(
        data['reason']?.toString() ??
            'Question generation abstained — insufficient textbook evidence.',
      );
    }

    return Question.fromJson(data);
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse(baseUrl + path).replace(queryParameters: queryParams);
    try {
      final resp = await _http.get(uri).timeout(timeout);
      return _handleResponse(resp);
    } on TimeoutException {
      throw const ApiException('Request timed out');
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } catch (e) {
      throw ApiException('Unexpected network error: $e');
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> body,
    Duration? customTimeout,
  }) async {
    final uri = Uri.parse(baseUrl + path);
    try {
      final resp = await _http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(customTimeout ?? timeout);

      if (resp.statusCode == 503) {
        String msg = 'Live generation service unavailable';
        try {
          msg = (jsonDecode(resp.body) as Map)['error']?.toString() ?? msg;
        } catch (_) {}
        throw LiveGenerationUnavailableException(msg);
      }
      return _handleResponse(resp);
    } on TimeoutException {
      throw const ApiException('Request timed out — the AI is taking too long. Try again.');
    } on LiveGenerationUnavailableException {
      rethrow;
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Unexpected error: $e');
    }
  }

  Map<String, dynamic> _handleResponse(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      try {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        throw ApiException('Invalid response format', statusCode: resp.statusCode);
      }
    }
    String message = 'Server error';
    try {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      message = body['error']?.toString() ?? message;
    } catch (_) {}
    throw ApiException(message, statusCode: resp.statusCode);
  }

  void dispose() => _http.close();
}
