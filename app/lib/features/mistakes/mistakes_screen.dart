// lib/features/mistakes/mistakes_screen.dart
// Progressive navigation drill-down for mistake questions:
// Screen 1: Subject Cards ONLY
// Screen 2: Chapter List for selected Subject
// Screen 3: Mistake Question Cards for selected Chapter

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/question.dart';
import '../../data/models/subject.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../practice/practice_screen.dart';

/// Screen 1: Displays only Subject Cards for mistake questions
class MistakesScreen extends StatefulWidget {
  const MistakesScreen({super.key});

  @override
  State<MistakesScreen> createState() => _MistakesScreenState();
}

class _MistakesScreenState extends State<MistakesScreen> {
  List<Question>? _questions;
  bool _loading = true;
  String? _error;

  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final progress = context.read<ProgressRepository>();
      final qRepo = context.read<QuestionRepository>();
      final incorrectIds = await progress.getIncorrectQuestionIds(_studentId);
      final loaded = await qRepo.getQuestionsByIds(incorrectIds);
      if (mounted) {
        setState(() {
          _questions = loaded;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _startPracticeSession(List<Question> questionsToPractice, {String? title}) {
    if (questionsToPractice.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          subjectId: questionsToPractice.first.subjectId,
          chapterId: questionsToPractice.first.chapterId,
          chapterTitle: title ?? 'Mistake Vault Drill',
          mode: 'mistake_review',
          initialQuestions: questionsToPractice,
        ),
      ),
    ).then((_) => _load());
  }

  Future<void> _confirmClearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark All as Resolved?'),
        content: const Text(
          'This will clear your active mistake review list. You can build it again by practising chapters.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (!mounted) return;
      final progress = context.read<ProgressRepository>();
      await progress.clearAllMistakes(_studentId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = SubjectGroup.groupQuestions(_questions ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mistake Vault'),
        actions: [
          if (_questions != null && _questions!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: BounceTap(
                onTap: () => _startPracticeSession(_questions!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.incorrectLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.incorrectBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay_rounded, size: 16, color: AppColors.incorrect),
                      SizedBox(width: 4),
                      Text(
                        'Practise All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.incorrect,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (val) {
                if (val == 'clear_all') _confirmClearAll();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear_all',
                  child: Row(
                    children: [
                      Icon(Icons.done_all_rounded, size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Mark All as Resolved'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: _buildBody(groups),
    );
  }

  Widget _buildBody(List<SubjectGroup> groups) {
    if (_loading) return const LoadingState(message: 'Loading mistake review list…');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_questions == null || _questions!.isEmpty) {
      return EmptyState(
        message: "You're all caught up! Zero active mistakes.\nKeep practising chapters to build and master your knowledge.",
        icon: Icons.check_circle_rounded,
        actionLabel: 'Start Practising',
        onAction: () => Navigator.popUntil(context, ModalRoute.withName('/')),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Bento Summary Card
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.incorrectLight,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.incorrectBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.incorrectBorder),
                  ),
                  child: const Icon(
                    Icons.replay_rounded,
                    size: 22,
                    color: AppColors.incorrect,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_questions!.length} Question${_questions!.length == 1 ? '' : 's'} for Revision',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.incorrect,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select a subject to review mistakes (${groups.length} subject${groups.length == 1 ? '' : 's'})',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Subject Cards Only
          for (final subjectGroup in groups) ...[
            _MistakeSubjectNavigationCard(
              subjectGroup: subjectGroup,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MistakeChaptersScreen(
                      subjectGroup: subjectGroup,
                    ),
                  ),
                ).then((_) => _load());
              },
              onPractise: () => _startPracticeSession(
                subjectGroup.chapters.expand((c) => c.questions).toList(),
                title: '${subjectGroup.subjectTitle} Mistakes Drill',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Subject Card widget displaying subject icon, title, mistake count pill and arrow
class _MistakeSubjectNavigationCard extends StatelessWidget {
  final SubjectGroup subjectGroup;
  final VoidCallback onTap;
  final VoidCallback onPractise;

  const _MistakeSubjectNavigationCard({
    required this.subjectGroup,
    required this.onTap,
    required this.onPractise,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Subject.getAccentColor(subjectGroup.subjectId);
    final surface = Subject.getSurfaceColor(subjectGroup.subjectId);
    final icon = Subject.getIconData(subjectGroup.subjectId);

    return BounceTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x050F172A),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subjectGroup.subjectTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${subjectGroup.totalQuestions} mistake${subjectGroup.totalQuestions == 1 ? '' : 's'} across ${subjectGroup.chapters.length} chapter${subjectGroup.chapters.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            BounceTap(
              onTap: onPractise,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.replay_rounded, size: 14, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      'Practise',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: accent, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Screen 2: Displays the Chapter List with mistakes for a chosen Subject
class MistakeChaptersScreen extends StatefulWidget {
  final SubjectGroup subjectGroup;

  const MistakeChaptersScreen({
    super.key,
    required this.subjectGroup,
  });

  @override
  State<MistakeChaptersScreen> createState() => _MistakeChaptersScreenState();
}

class _MistakeChaptersScreenState extends State<MistakeChaptersScreen> {
  late SubjectGroup _subjectGroup;
  bool _loading = false;

  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _subjectGroup = widget.subjectGroup;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final progress = context.read<ProgressRepository>();
      final qRepo = context.read<QuestionRepository>();
      final incorrectIds = await progress.getIncorrectQuestionIds(_studentId);
      final loaded = await qRepo.getQuestionsByIds(incorrectIds);
      final subQuestions = loaded.where((q) => q.subjectId == widget.subjectGroup.subjectId).toList();
      final groups = SubjectGroup.groupQuestions(subQuestions);
      if (mounted) {
        setState(() {
          if (groups.isNotEmpty) {
            _subjectGroup = groups.first;
          } else {
            _subjectGroup = SubjectGroup(
              subjectId: widget.subjectGroup.subjectId,
              subjectTitle: widget.subjectGroup.subjectTitle,
              chapters: [],
            );
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startPracticeSession(List<Question> questionsToPractice, {String? title}) {
    if (questionsToPractice.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          subjectId: questionsToPractice.first.subjectId,
          chapterId: questionsToPractice.first.chapterId,
          chapterTitle: title ?? '${_subjectGroup.subjectTitle} Mistakes Drill',
          mode: 'mistake_review',
          initialQuestions: questionsToPractice,
        ),
      ),
    ).then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    final accent = Subject.getAccentColor(_subjectGroup.subjectId);
    final surface = Subject.getSurfaceColor(_subjectGroup.subjectId);
    final icon = Subject.getIconData(_subjectGroup.subjectId);

    return Scaffold(
      appBar: AppBar(
        title: Text('${_subjectGroup.subjectTitle} Mistakes'),
        actions: [
          if (_subjectGroup.totalQuestions > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BounceTap(
                onTap: () => _startPracticeSession(
                  _subjectGroup.chapters.expand((c) => c.questions).toList(),
                  title: '${_subjectGroup.subjectTitle} Mistakes Drill',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay_rounded, size: 14, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        'Practise Subject',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const LoadingState(message: 'Loading chapters…')
          : _subjectGroup.chapters.isEmpty
              ? EmptyState(
                  message: 'Zero active mistakes in ${_subjectGroup.subjectTitle}!',
                  icon: Icons.check_circle_outline_rounded,
                  actionLabel: 'Back to Subjects',
                  onAction: () => Navigator.pop(context),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  children: [
                    // Header Bento Card
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: accent.withValues(alpha: 0.4)),
                            ),
                            child: Icon(icon, color: accent, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _subjectGroup.subjectTitle,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_subjectGroup.totalQuestions} mistakes across ${_subjectGroup.chapters.length} chapters. Tap a chapter to review questions.',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Chapter Cards List
                    for (final ch in _subjectGroup.chapters) ...[
                      _MistakeChapterNavigationCard(
                        chapterGroup: ch,
                        accentColor: accent,
                        surfaceColor: surface,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MistakeChapterQuestionsScreen(
                                subjectGroup: _subjectGroup,
                                chapterGroup: ch,
                              ),
                            ),
                          ).then((_) => _refresh());
                        },
                        onPractise: () => _startPracticeSession(
                          ch.questions,
                          title: ch.chapterTitle,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
    );
  }
}

/// Mistake Chapter Navigation Card
class _MistakeChapterNavigationCard extends StatelessWidget {
  final ChapterGroup chapterGroup;
  final Color accentColor;
  final Color surfaceColor;
  final VoidCallback onTap;
  final VoidCallback onPractise;

  const _MistakeChapterNavigationCard({
    required this.chapterGroup,
    required this.accentColor,
    required this.surfaceColor,
    required this.onTap,
    required this.onPractise,
  });

  @override
  Widget build(BuildContext context) {
    return BounceTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x050F172A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.menu_book_rounded, color: accentColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapterGroup.chapterTitle,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${chapterGroup.questions.length} mistake${chapterGroup.questions.length == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            BounceTap(
              onTap: onPractise,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.incorrectBorder),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.replay_rounded, size: 13, color: AppColors.incorrect),
                    SizedBox(width: 4),
                    Text(
                      'Practise',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.incorrect,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Screen 3: Displays the list of Mistake Question Cards for a specific Chapter
class MistakeChapterQuestionsScreen extends StatefulWidget {
  final SubjectGroup subjectGroup;
  final ChapterGroup chapterGroup;

  const MistakeChapterQuestionsScreen({
    super.key,
    required this.subjectGroup,
    required this.chapterGroup,
  });

  @override
  State<MistakeChapterQuestionsScreen> createState() => _MistakeChapterQuestionsScreenState();
}

class _MistakeChapterQuestionsScreenState extends State<MistakeChapterQuestionsScreen> {
  late List<Question> _questions;
  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _questions = List.from(widget.chapterGroup.questions);
  }

  Future<void> _onQuestionResolved(Question question) async {
    final progress = context.read<ProgressRepository>();
    await progress.resolveMistake(
      localStudentId: _studentId,
      questionId: question.questionId,
    );
    if (!mounted) return;
    setState(() {
      _questions.removeWhere((q) => q.questionId == question.questionId);
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Question resolved and cleared from Mistake Vault'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _startPracticeSession(List<Question> questionsToPractice) {
    if (questionsToPractice.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          subjectId: widget.subjectGroup.subjectId,
          chapterId: widget.chapterGroup.chapterId,
          chapterTitle: widget.chapterGroup.chapterTitle,
          mode: 'mistake_review',
          initialQuestions: questionsToPractice,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterGroup.chapterTitle),
        actions: [
          if (_questions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BounceTap(
                onTap: () => _startPracticeSession(_questions),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.incorrectLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.incorrectBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay_rounded, size: 14, color: AppColors.incorrect),
                      SizedBox(width: 4),
                      Text(
                        'Practise Chapter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.incorrect,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _questions.isEmpty
          ? EmptyState(
              message: 'All mistakes in this chapter have been resolved!',
              icon: Icons.check_circle_outline_rounded,
              actionLabel: 'Back to Chapters',
              onAction: () => Navigator.pop(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              itemCount: _questions.length,
              itemBuilder: (ctx, i) {
                final q = _questions[i];
                return _MistakeCard(
                  key: ValueKey(q.questionId),
                  question: q,
                  onResolved: () => _onQuestionResolved(q),
                );
              },
            ),
    );
  }
}

class _MistakeCard extends StatefulWidget {
  final Question question;
  final VoidCallback onResolved;

  const _MistakeCard({
    super.key,
    required this.question,
    required this.onResolved,
  });

  @override
  State<_MistakeCard> createState() => _MistakeCardState();
}

class _MistakeCardState extends State<_MistakeCard> {
  bool _retryMode = false;
  String? _selectedOptionId;
  bool? _isRetryCorrect;
  bool _isSaved = false;

  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _checkSaved();
  }

  Future<void> _checkSaved() async {
    try {
      final qRepo = context.read<QuestionRepository>();
      final saved = await qRepo.isQuestionSaved(widget.question.questionId, studentId: _studentId);
      if (mounted) setState(() => _isSaved = saved);
    } catch (_) {}
  }

  Future<void> _toggleSave() async {
    try {
      final qRepo = context.read<QuestionRepository>();
      final saved = await qRepo.toggleSaveQuestion(widget.question, studentId: _studentId);
      if (!mounted) return;
      setState(() => _isSaved = saved);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved ? 'Question saved to bookmarks' : 'Question removed from bookmarks',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (_) {}
  }

  Future<void> _handleOptionSelected(String optionId) async {
    if (_isRetryCorrect == true) return;
    final isCorrect = optionId == widget.question.correctOptionId;
    setState(() {
      _selectedOptionId = optionId;
      _isRetryCorrect = isCorrect;
    });

    if (isCorrect) {
      final progress = context.read<ProgressRepository>();
      await progress.recordAttempt(
        localStudentId: _studentId,
        questionId: widget.question.questionId,
        selectedOptionId: optionId,
        isCorrect: true,
        mode: 'mistake_review',
        questionContentVersion: widget.question.contentVersion,
      );

      // Delay briefly so student sees the positive feedback, then trigger resolve
      await Future.delayed(const Duration(milliseconds: 1000));
      if (mounted) {
        widget.onResolved();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final correctOpt = question.options.firstWhere(
      (o) => o.optionId == question.correctOptionId,
      orElse: () => QuestionOption(optionId: question.correctOptionId, text: ''),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x050F172A),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  question.chapterTitle.isNotEmpty
                      ? question.chapterTitle
                      : 'Class 10 Syllabus',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              OriginBadge(origin: question.origin),
              const SizedBox(width: 8),
              Tooltip(
                message: _isSaved ? 'Remove from saved' : 'Save question',
                child: BounceTap(
                  onTap: _toggleSave,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isSaved ? AppColors.primaryLight : AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSaved ? const Color(0xFFBFDBFE) : AppColors.divider,
                      ),
                    ),
                    child: Icon(
                      _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                      size: 18,
                      color: _isSaved ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question.questionText,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.45,
              letterSpacing: -0.2,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Either Interactive Retry Mode OR Review Mode
          if (_retryMode) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.help_outline_rounded, size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'SELECT THE CORRECT OPTION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...question.options.map((opt) {
                    final isSelected = _selectedOptionId == opt.optionId;
                    Color optBg = AppColors.surface;
                    Color optBorder = AppColors.divider;
                    Color textColor = AppColors.textPrimary;

                    if (isSelected) {
                      if (_isRetryCorrect == true) {
                        optBg = AppColors.correctLight;
                        optBorder = AppColors.correct;
                        textColor = AppColors.correct;
                      } else if (_isRetryCorrect == false) {
                        optBg = AppColors.incorrectLight;
                        optBorder = AppColors.incorrect;
                        textColor = AppColors.incorrect;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: BounceTap(
                        onTap: () => _handleOptionSelected(opt.optionId),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: optBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: optBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text(
                                    opt.optionId,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  opt.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_isRetryCorrect == true)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.correctLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.correct, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Mastered! Resolving mistake…',
                            style: TextStyle(
                              color: AppColors.correct,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ] else ...[
            // Standard Review Mode: Shows verified correct answer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.correctLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.correctBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.correct,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Correct: Option ${question.correctOptionId} — ${correctOpt.text}',
                      style: const TextStyle(
                        color: AppColors.correct,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (question.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.menu_book_rounded,
                          size: 14, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text(
                        'EXPLANATION & TEXTBOOK CONCEPT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    question.explanation,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (question.sourceRefs.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: question.sourceRefs
                  .map((r) => SourceRefChip(
                        pageLabel: r.printedPageLabel,
                        chapterTitle: r.chapterTitle,
                      ))
                  .toList(),
            ),
          ],

          const SizedBox(height: 14),
          Row(
            children: [
              TextButton.icon(
                onPressed: widget.onResolved,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Mark Resolved'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              BounceTap(
                onTap: () {
                  setState(() {
                    _retryMode = !_retryMode;
                    _selectedOptionId = null;
                    _isRetryCorrect = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _retryMode ? AppColors.surfaceSubtle : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _retryMode ? AppColors.divider : const Color(0xFFBFDBFE),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _retryMode ? Icons.visibility_outlined : Icons.replay_rounded,
                        size: 15,
                        color: _retryMode ? AppColors.textSecondary : AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _retryMode ? 'View Solution' : 'Retry Now',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _retryMode ? AppColors.textSecondary : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
