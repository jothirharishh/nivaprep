// test/widget_test.dart
// Widget tests for BoardMate 10.
// These tests do not require a live API or Groq.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:boardmate10/core/networking/api_client.dart';
import 'package:boardmate10/core/widgets/common_widgets.dart';
import 'package:boardmate10/data/models/question.dart';
import 'package:boardmate10/data/repositories/question_repository.dart';
import 'package:boardmate10/data/repositories/progress_repository.dart';
import 'package:boardmate10/features/subjects/subject_provider.dart';
import 'package:boardmate10/features/splash/splash_screen.dart';
import 'package:boardmate10/features/saved/saved_questions_screen.dart';
import 'package:boardmate10/features/mistakes/mistakes_screen.dart';
import 'package:boardmate10/main.dart';

// Fake implementations for testing without SQLite or live network
class FakeQuestionRepository implements QuestionRepository {
  final List<Question> savedQuestions = [];
  final Map<String, Question> questionBank = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> isQuestionSaved(String questionId, {String studentId = 'local_anon'}) async {
    return savedQuestions.any((q) => q.questionId == questionId);
  }

  @override
  Future<bool> toggleSaveQuestion(Question question, {String studentId = 'local_anon'}) async {
    final idx = savedQuestions.indexWhere((q) => q.questionId == question.questionId);
    if (idx >= 0) {
      savedQuestions.removeAt(idx);
      return false;
    } else {
      savedQuestions.add(question);
      return true;
    }
  }

  @override
  Future<void> removeSavedQuestion(String questionId, {String studentId = 'local_anon'}) async {
    savedQuestions.removeWhere((q) => q.questionId == questionId);
  }

  @override
  Future<List<Question>> getSavedQuestions({String studentId = 'local_anon'}) async {
    return List.from(savedQuestions);
  }

  @override
  Future<int> getSavedCount({String studentId = 'local_anon'}) async {
    return savedQuestions.length;
  }

  @override
  Future<List<Question>> getQuestionsByIds(List<String> ids) async {
    return ids.map((id) => questionBank[id]).whereType<Question>().toList();
  }

  @override
  Future<void> cacheQuestion(Question question) async {
    questionBank[question.questionId] = question;
  }
}

class FakeProgressRepository implements ProgressRepository {
  final List<String> incorrectIds = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<List<String>> getIncorrectQuestionIds(String localStudentId) async {
    return List.from(incorrectIds);
  }

  @override
  Future<int> getActiveMistakeCount(String localStudentId) async {
    return incorrectIds.length;
  }

  @override
  Future<void> resolveMistake({required String localStudentId, required String questionId}) async {
    incorrectIds.remove(questionId);
  }

  @override
  Future<void> clearAllMistakes(String localStudentId) async {
    incorrectIds.clear();
  }

  @override
  Future<void> resetAllRecords(String localStudentId) async {
    incorrectIds.clear();
  }

  @override
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
    if (isCorrect) {
      incorrectIds.remove(questionId);
    } else {
      if (!incorrectIds.contains(questionId)) incorrectIds.add(questionId);
    }
    return 'attempt_123';
  }
}

Question createSampleQuestion({
  String id = 'q001',
  String subjectId = 'science',
  String chapterId = 'ch_electricity',
  String chapterTitle = 'Electricity',
  String text = 'What is the unit of electric current?',
  String correctOption = 'A',
}) {
  return Question(
    questionId: id,
    subjectId: subjectId,
    sourceId: 'src_$subjectId',
    chapterId: chapterId,
    chapterTitle: chapterTitle,
    language: 'en',
    origin: QuestionOrigin.textbook,
    questionText: text,
    options: const [
      QuestionOption(optionId: 'A', text: 'Ampere'),
      QuestionOption(optionId: 'B', text: 'Volt'),
      QuestionOption(optionId: 'C', text: 'Ohm'),
      QuestionOption(optionId: 'D', text: 'Watt'),
    ],
    correctOptionId: correctOption,
    explanation: 'Ampere is the SI unit of electric current named after André-Marie Ampère.',
    sourceRefs: [
      SourceRef(
        passageId: 'pass_01',
        chapterTitle: chapterTitle,
        printedPageLabel: 'p. 42',
      ),
    ],
    difficulty: 'medium',
    contentVersion: 1,
  );
}

void main() {
  group('OriginBadge', () {
    testWidgets('shows "Textbook" for textbook origin', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginBadge(origin: QuestionOrigin.textbook)),
        ),
      );
      expect(find.text('Textbook'), findsOneWidget);
    });

    testWidgets('shows "AI Practice" for aiGenerated origin', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OriginBadge(origin: QuestionOrigin.aiGenerated)),
        ),
      );
      expect(find.text('AI Practice'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders message text', (tester) async {
      const msg = 'No verified questions available yet.';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EmptyState(message: msg)),
        ),
      );
      expect(find.text(msg), findsOneWidget);
    });
  });

  group('LoadingState', () {
    testWidgets('shows CircularProgressIndicator', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingState(message: 'Loading…')),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('ErrorState', () {
    testWidgets('shows retry button when onRetry provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorState(
              message: 'Could not load',
              onRetry: () {},
            ),
          ),
        ),
      );
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('no retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ErrorState(message: 'Error')),
        ),
      );
      expect(find.text('Try again'), findsNothing);
    });
  });

  group('Question model', () {
    test('fromJson parses correctly', () {
      final json = {
        'question_id': 'q001',
        'subject_id': 'science',
        'source_id': 'src001',
        'chapter_id': 'ch01',
        'chapter_title': 'Chemical Reactions',
        'language': 'en',
        'origin': 'ai_generated',
        'question_text': 'What is H2O?',
        'options': [
          {'option_id': 'A', 'text': 'Water'},
          {'option_id': 'B', 'text': 'CO2'},
          {'option_id': 'C', 'text': 'Salt'},
          {'option_id': 'D', 'text': 'HCl'},
        ],
        'correct_option_id': 'A',
        'explanation': 'H2O is water.',
        'source_refs': [],
        'difficulty': 'easy',
        'content_version': 1,
      };
      final q = Question.fromJson(json);
      expect(q.questionId, 'q001');
      expect(q.origin, QuestionOrigin.aiGenerated);
      expect(q.options.length, 4);
      expect(q.correctOptionId, 'A');
    });

    test('origin label is correct', () {
      expect(QuestionOriginExt.fromString('textbook').displayLabel,
          'Textbook Question');
      expect(QuestionOriginExt.fromString('adapted').displayLabel,
          'Adapted Question');
      expect(QuestionOriginExt.fromString('ai_generated').displayLabel,
          'AI-Generated Practice');
    });
  });

  group('SavedQuestionsScreen', () {
    testWidgets('renders empty state when no questions are saved', (tester) async {
      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: SavedQuestionsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('No saved questions yet'), findsOneWidget);
    });

    testWidgets('renders saved question card and allows unsaving', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();
      final sampleQ = createSampleQuestion();
      fakeQRepo.savedQuestions.add(sampleQ);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: SavedQuestionsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Practise All'), findsOneWidget);
      // Screen 1: Subject Cards ONLY
      expect(find.text('Science'), findsOneWidget);

      // Tap Science subject to navigate to SavedChaptersScreen (Screen 2)
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      expect(find.text('Science Saved Chapters'), findsOneWidget);
      expect(find.text('Electricity'), findsWidgets);

      // Tap Electricity chapter to navigate to SavedChapterQuestionsScreen (Screen 3)
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();
      expect(find.text(sampleQ.questionText), findsOneWidget);

      // Find and tap remove bookmark
      final bookmarkBtn = find.byTooltip('Remove bookmark');
      expect(bookmarkBtn, findsOneWidget);
      await tester.tap(bookmarkBtn);
      await tester.pumpAndSettle();

      expect(fakeQRepo.savedQuestions, isEmpty);
      expect(find.textContaining('All saved questions in this chapter have been removed'), findsOneWidget);

      // Tap 'Back to Chapters'
      await tester.tap(find.text('Back to Chapters'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No saved questions left in Science'), findsOneWidget);

      // Tap 'Back to Subjects'
      await tester.tap(find.text('Back to Subjects'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No saved questions yet'), findsOneWidget);
    });

    testWidgets('organizes questions under subjects and chapters with progressive drill-down', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();

      final scienceQ = createSampleQuestion(
        id: 'q_sci_1',
        subjectId: 'science',
        chapterId: 'ch_electricity',
        chapterTitle: 'Electricity',
        text: 'What is the unit of electric current?',
      );
      final mathsQ = createSampleQuestion(
        id: 'q_math_1',
        subjectId: 'mathematics',
        chapterId: 'ch_relations',
        chapterTitle: 'Relations and Functions',
        text: 'What is a relation?',
      );

      fakeQRepo.savedQuestions.addAll([scienceQ, mathsQ]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: SavedQuestionsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 1: User first sees Subject Cards ONLY
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('Electricity'), findsNothing);
      expect(find.text('Relations and Functions'), findsNothing);

      // Step 2: Tap Science -> Chapter List for Science appears
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      expect(find.text('Science Saved Chapters'), findsOneWidget);
      expect(find.text('Electricity'), findsWidgets);
      expect(find.text('Relations and Functions'), findsNothing);

      // Step 3: Tap Electricity -> Questions for Electricity appear
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();
      expect(find.text(scienceQ.questionText), findsOneWidget);

      // Step 4: Pop back to Chapters screen, then back to Subjects screen
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Science Saved Chapters'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics'), findsOneWidget);

      // Step 5: Tap Mathematics -> Chapter List for Mathematics appears
      await tester.tap(find.text('Mathematics'));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics Saved Chapters'), findsOneWidget);
      expect(find.text('Relations and Functions'), findsWidgets);

      // Step 6: Tap Relations and Functions -> Questions appear
      await tester.tap(find.text('Relations and Functions').first);
      await tester.pumpAndSettle();
      expect(find.text(mathsQ.questionText), findsOneWidget);
    });
  });

  group('MistakesScreen', () {
    testWidgets('renders caught-up state when no mistakes exist', (tester) async {
      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: MistakesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Zero active mistakes'), findsOneWidget);
    });

    testWidgets('renders mistake card and allows interactive retry', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();
      final sampleQ = createSampleQuestion(id: 'q_mistake_1');
      fakeQRepo.questionBank[sampleQ.questionId] = sampleQ;
      fakeProg.incorrectIds.add(sampleQ.questionId);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: MistakesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('1 Question for Revision'), findsOneWidget);
      // Screen 1: Subject Cards ONLY
      expect(find.text('Science'), findsOneWidget);

      // Tap subject Science to navigate to MistakeChaptersScreen (Screen 2)
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      expect(find.text('Science Mistakes'), findsOneWidget);
      expect(find.text('Electricity'), findsWidgets);

      // Tap chapter Electricity to navigate to MistakeChapterQuestionsScreen (Screen 3)
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();
      expect(find.text(sampleQ.questionText), findsOneWidget);
      expect(find.text('Retry Now'), findsOneWidget);

      // Tap Retry Now to enter interactive retry mode
      await tester.tap(find.text('Retry Now'));
      await tester.pumpAndSettle();

      expect(find.text('SELECT THE CORRECT OPTION'), findsOneWidget);
      expect(find.text('Ampere'), findsOneWidget);

      // Tap correct option
      await tester.tap(find.text('Ampere'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();

      // Mistake is resolved and removed from vault
      expect(fakeProg.incorrectIds, isEmpty);
      expect(find.textContaining('All mistakes in this chapter have been resolved'), findsOneWidget);

      // Navigate back to Chapters
      await tester.tap(find.text('Back to Chapters'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zero active mistakes in Science'), findsOneWidget);

      // Navigate back to Subjects
      await tester.tap(find.text('Back to Subjects'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Zero active mistakes'), findsOneWidget);
    });

    testWidgets('organizes mistakes under subjects and chapters with progressive drill-down', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();

      final scienceQ = createSampleQuestion(
        id: 'q_m_sci_1',
        subjectId: 'science',
        chapterId: 'ch_electricity',
        chapterTitle: 'Electricity',
        text: 'What is electric current?',
      );
      final mathsQ = createSampleQuestion(
        id: 'q_m_math_1',
        subjectId: 'mathematics',
        chapterId: 'ch_relations',
        chapterTitle: 'Relations and Functions',
        text: 'What is a function?',
      );

      fakeQRepo.questionBank[scienceQ.questionId] = scienceQ;
      fakeQRepo.questionBank[mathsQ.questionId] = mathsQ;
      fakeProg.incorrectIds.addAll([scienceQ.questionId, mathsQ.questionId]);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
          ],
          child: const MaterialApp(
            home: MistakesScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 1: User first sees Subject Cards ONLY
      expect(find.text('Science'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);
      expect(find.text('Electricity'), findsNothing);
      expect(find.text('Relations and Functions'), findsNothing);

      // Step 2: Tap Science -> Chapter List appears
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      expect(find.text('Science Mistakes'), findsOneWidget);
      expect(find.text('Electricity'), findsWidgets);
      expect(find.text('Relations and Functions'), findsNothing);

      // Step 3: Tap Electricity -> Questions appear
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();
      expect(find.text(scienceQ.questionText), findsOneWidget);

      // Step 4: Back to Chapters, then back to Subjects
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Science Mistakes'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics'), findsOneWidget);

      // Step 5: Tap Mathematics -> Chapter List appears
      await tester.tap(find.text('Mathematics'));
      await tester.pumpAndSettle();
      expect(find.text('Mathematics Mistakes'), findsOneWidget);
      expect(find.text('Relations and Functions'), findsWidgets);

      // Step 6: Tap Relations and Functions -> Questions appear
      await tester.tap(find.text('Relations and Functions').first);
      await tester.pumpAndSettle();
      expect(find.text(mathsQ.questionText), findsOneWidget);
    });
  });

  group('MainShell NavigationBar', () {
    testWidgets('tapping Saved and Mistakes navbar icons displays respective questions', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeQRepo = FakeQuestionRepository();
      final fakeProg = FakeProgressRepository();
      final sampleQ1 = createSampleQuestion(id: 'q_saved_1', text: 'Saved Question Alpha');
      final sampleQ2 = createSampleQuestion(id: 'q_mistake_2', text: 'Mistake Question Beta');

      fakeQRepo.savedQuestions.add(sampleQ1);
      fakeQRepo.questionBank[sampleQ2.questionId] = sampleQ2;
      fakeProg.incorrectIds.add(sampleQ2.questionId);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<QuestionRepository>.value(value: fakeQRepo),
            Provider<ProgressRepository>.value(value: fakeProg),
            ChangeNotifierProvider<SubjectProvider>(
              create: (_) => SubjectProvider(api: ApiClient(baseUrl: 'http://localhost:5000')),
            ),
          ],
          child: const BoardMateApp(),
        ),
      );

      await tester.pumpAndSettle();

      // On launch, Explore tab is active
      expect(find.text('Explore'), findsOneWidget);

      // Tap "Saved" in the NavigationBar
      await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
      await tester.pumpAndSettle();

      // SavedQuestionsScreen shows subject card and total count
      expect(find.text('1 Bookmarked Question'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);

      // Tap to navigate to Subject and Chapter
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();

      expect(find.text('Saved Question Alpha'), findsOneWidget);

      // Pop back from questions and chapters to main shell
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // Tap "Mistakes" in the NavigationBar
      await tester.tap(find.byIcon(Icons.replay_outlined));
      await tester.pumpAndSettle();

      // MistakesScreen shows subject card and total count
      expect(find.text('1 Question for Revision'), findsOneWidget);
      expect(find.text('Science'), findsOneWidget);

      // Tap to navigate to Subject and Chapter
      await tester.tap(find.text('Science'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electricity').first);
      await tester.pumpAndSettle();

      expect(find.text('Mistake Question Beta'), findsOneWidget);
    });
  });

  group('SplashScreen', () {
    testWidgets('renders brand title, edition tag, and badge', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SubjectProvider>(
              create: (_) => SubjectProvider(api: ApiClient(baseUrl: 'http://localhost:5000')),
            ),
          ],
          child: const MaterialApp(
            home: SplashScreen(),
          ),
        ),
      );

      expect(find.text('BoardMate 10'), findsOneWidget);
      expect(find.text('Tamil Nadu Samacheer Kalvi Class 10'), findsOneWidget);
      expect(find.text('AI Textbook Quiz • 100% Verified'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 2000));
    });
  });
}
