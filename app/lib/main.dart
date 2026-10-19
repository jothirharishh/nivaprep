// lib/main.dart
// BoardMate 10 — Android study app for Tamil Nadu Samacheer Kalvi Class 10.
// Groq credentials are NEVER stored in this app.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/networking/api_client.dart';
import 'core/storage/local_database.dart';
import 'data/repositories/question_repository.dart';
import 'data/repositories/progress_repository.dart';
import 'features/splash/splash_screen.dart';
import 'features/subjects/subject_provider.dart';
import 'features/home/home_screen.dart';
import 'features/saved/saved_questions_screen.dart';
import 'features/mistakes/mistakes_screen.dart';
import 'features/progress/progress_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/chapters/chapters_screen.dart';
import 'features/practice/practice_screen.dart';
import 'data/models/subject.dart';

// Default to local/emulator; override in release with --dart-define=API_URL=https://your-service.onrender.com
const _apiBaseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: kIsWeb ? 'http://127.0.0.1:5000' : 'http://10.0.2.2:5000',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localDb = LocalDatabase();
  final api = ApiClient(baseUrl: _apiBaseUrl);

  runApp(
    MultiProvider(
      providers: [
        Provider<LocalDatabase>.value(value: localDb),
        Provider<ApiClient>.value(value: api),
        Provider<QuestionRepository>(
          create: (_) => QuestionRepository(api: api, localDb: localDb),
        ),
        Provider<ProgressRepository>(
          create: (_) => ProgressRepository(localDb: localDb),
        ),
        ChangeNotifierProvider<SubjectProvider>(
          create: (_) => SubjectProvider(api: api),
        ),
      ],
      child: const BoardMateApp(),
    ),
  );
}

class BoardMateApp extends StatelessWidget {
  const BoardMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoardMate 10',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
      onGenerateRoute: _generateRoute,
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/main':
        return MaterialPageRoute(builder: (_) => const MainShell());
      case '/settings':
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case '/chapters':
        final subject = settings.arguments as Subject;
        return MaterialPageRoute(
          builder: (_) => ChaptersScreen(subject: subject),
        );
      case '/mode-select':
        final chapter = settings.arguments as Chapter;
        return MaterialPageRoute(
          builder: (_) => PracticeScreen(
            subjectId: chapter.subjectId,
            chapterId: chapter.chapterId,
            chapterTitle: chapter.title,
            mode: 'practice',
          ),
        );
      case '/practice':
        return MaterialPageRoute(builder: (_) => const _PracticePlaceholder());
      case '/saved':
        return MaterialPageRoute(builder: (_) => const SavedQuestionsScreen());
      case '/mistakes':
        return MaterialPageRoute(builder: (_) => const MistakesScreen());
      default:
        return null;
    }
  }
}

class MainShellScope extends InheritedWidget {
  final ValueChanged<int> selectTab;
  const MainShellScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  static MainShellScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainShellScope>();

  @override
  bool updateShouldNotify(MainShellScope oldWidget) => false;
}

/// Bottom navigation shell with 4 tabs.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  int _tabRefreshKey = 0;

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _tabRefreshKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MainShellScope(
      selectTab: _selectTab,
      child: Scaffold(
        body: KeyedSubtree(
          key: ValueKey('tab_${_selectedIndex}_$_tabRefreshKey'),
          child: switch (_selectedIndex) {
            0 => const HomeScreen(),
            1 => const SavedQuestionsScreen(),
            2 => const MistakesScreen(),
            3 => const ProgressScreen(),
            _ => const HomeScreen(),
          },
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
          ),
          child: NavigationBar(
            selectedIndex: _selectedIndex,
            height: 64,
            elevation: 0,
            backgroundColor: AppColors.surface,
            onDestinationSelected: _selectTab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined, size: 22),
                selectedIcon: Icon(Icons.grid_view_rounded, size: 22, color: AppColors.primary),
                label: 'Explore',
              ),
              NavigationDestination(
                icon: Icon(Icons.bookmark_outline_rounded, size: 22),
                selectedIcon: Icon(Icons.bookmark_rounded, size: 22, color: AppColors.primary),
                label: 'Saved',
              ),
              NavigationDestination(
                icon: Icon(Icons.replay_outlined, size: 22),
                selectedIcon: Icon(Icons.replay_rounded, size: 22, color: AppColors.primary),
                label: 'Mistakes',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined, size: 22),
                selectedIcon: Icon(Icons.insights_rounded, size: 22, color: AppColors.primary),
                label: 'Progress',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PracticePlaceholder extends StatelessWidget {
  const _PracticePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: const Center(
        child: Text('Select a subject and chapter from Home to practice.'),
      ),
    );
  }
}
