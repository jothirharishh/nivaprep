// lib/features/subjects/subject_provider.dart

import 'package:flutter/foundation.dart';
import '../../data/models/subject.dart';
import '../../core/networking/api_client.dart';

class SubjectProvider extends ChangeNotifier {
  final ApiClient api;

  List<Subject> subjects = [];
  bool isLoading = false;
  bool isOffline = false;
  String? error;

  SubjectProvider({required this.api}) {
    reload();
  }

  Future<void> reload() async {
    isLoading = true;
    error = null;
    isOffline = false;
    notifyListeners();
    try {
      subjects = await api.fetchSubjects();
    } on ApiException catch (e) {
      error = e.message;
      isOffline = e.statusCode == null;
    } catch (e) {
      error = 'Unexpected error: $e';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
