// lib/features/saved/saved_questions_screen.dart
// Progressive navigation drill-down for saved questions:
// Screen 1: Subject Cards ONLY
// Screen 2: Chapter List for selected Subject
// Screen 3: Saved Question Cards for selected Chapter

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/question.dart';
import '../../data/models/subject.dart';
import '../../data/repositories/question_repository.dart';
import '../practice/practice_screen.dart';

/// Screen 1: Displays only Subject Cards for saved questions
class SavedQuestionsScreen extends StatefulWidget {
  const SavedQuestionsScreen({super.key});

  @override
  State<SavedQuestionsScreen> createState() => _SavedQuestionsScreenState();
}

class _SavedQuestionsScreenState extends State<SavedQuestionsScreen> {
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
      final qRepo = context.read<QuestionRepository>();
      final list = await qRepo.getSavedQuestions(studentId: _studentId);
      if (mounted) {
        setState(() {
          _questions = list;
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
          chapterTitle: title ?? 'Saved Questions Practice',
          mode: 'practice',
          initialQuestions: questionsToPractice,
        ),
      ),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final groups = SubjectGroup.groupQuestions(_questions ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Questions'),
        actions: [
          if (_questions != null && _questions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BounceTap(
                onTap: () => _startPracticeSession(_questions!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Practise All',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(groups),
    );
  }

  Widget _buildBody(List<SubjectGroup> groups) {
    if (_loading) return const LoadingState(message: 'Loading saved questions…');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);

    if (_questions == null || _questions!.isEmpty) {
      return EmptyState(
        message: 'No saved questions yet.\nBookmark challenging questions during practice to review them anytime.',
        icon: Icons.bookmark_border_rounded,
        actionLabel: 'Browse Subjects',
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
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Icon(
                    Icons.bookmark_rounded,
                    size: 22,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_questions!.length} Bookmarked Question${_questions!.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select a subject to review saved questions (${groups.length} subject${groups.length == 1 ? '' : 's'})',
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
            _SubjectNavigationCard(
              subjectGroup: subjectGroup,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SavedChaptersScreen(
                      subjectGroup: subjectGroup,
                    ),
                  ),
                ).then((_) => _load());
              },
              onPractise: () => _startPracticeSession(
                subjectGroup.chapters.expand((c) => c.questions).toList(),
                title: '${subjectGroup.subjectTitle} Saved Practice',
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Subject Card widget displaying subject icon, title, count pill and arrow
class _SubjectNavigationCard extends StatelessWidget {
  final SubjectGroup subjectGroup;
  final VoidCallback onTap;
  final VoidCallback onPractise;

  const _SubjectNavigationCard({
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
                    '${subjectGroup.totalQuestions} question${subjectGroup.totalQuestions == 1 ? '' : 's'} across ${subjectGroup.chapters.length} chapter${subjectGroup.chapters.length == 1 ? '' : 's'}',
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
                    Icon(Icons.play_arrow_rounded, size: 15, color: accent),
                    const SizedBox(width: 3),
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

/// Screen 2: Displays the Chapter List for a chosen Subject
class SavedChaptersScreen extends StatefulWidget {
  final SubjectGroup subjectGroup;

  const SavedChaptersScreen({
    super.key,
    required this.subjectGroup,
  });

  @override
  State<SavedChaptersScreen> createState() => _SavedChaptersScreenState();
}

class _SavedChaptersScreenState extends State<SavedChaptersScreen> {
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
      final qRepo = context.read<QuestionRepository>();
      final list = await qRepo.getSavedQuestions(studentId: _studentId);
      final subQuestions = list.where((q) => q.subjectId == widget.subjectGroup.subjectId).toList();
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
          chapterTitle: title ?? '${_subjectGroup.subjectTitle} Practice',
          mode: 'practice',
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
        title: Text('${_subjectGroup.subjectTitle} Saved Chapters'),
        actions: [
          if (_subjectGroup.totalQuestions > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BounceTap(
                onTap: () => _startPracticeSession(
                  _subjectGroup.chapters.expand((c) => c.questions).toList(),
                  title: '${_subjectGroup.subjectTitle} Saved Practice',
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
                      Icon(Icons.play_arrow_rounded, size: 16, color: accent),
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
                  message: 'No saved questions left in ${_subjectGroup.subjectTitle}.',
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
                                  '${_subjectGroup.totalQuestions} questions across ${_subjectGroup.chapters.length} chapters. Tap a chapter to view questions.',
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
                      _ChapterNavigationCard(
                        chapterGroup: ch,
                        accentColor: accent,
                        surfaceColor: surface,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SavedChapterQuestionsScreen(
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

/// Chapter Navigation Card widget
class _ChapterNavigationCard extends StatelessWidget {
  final ChapterGroup chapterGroup;
  final Color accentColor;
  final Color surfaceColor;
  final VoidCallback onTap;
  final VoidCallback onPractise;

  const _ChapterNavigationCard({
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
                    '${chapterGroup.questions.length} saved question${chapterGroup.questions.length == 1 ? '' : 's'}',
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
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded, size: 14, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Practise',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
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

/// Screen 3: Displays the list of Saved Questions for a specific Chapter
class SavedChapterQuestionsScreen extends StatefulWidget {
  final SubjectGroup subjectGroup;
  final ChapterGroup chapterGroup;

  const SavedChapterQuestionsScreen({
    super.key,
    required this.subjectGroup,
    required this.chapterGroup,
  });

  @override
  State<SavedChapterQuestionsScreen> createState() => _SavedChapterQuestionsScreenState();
}

class _SavedChapterQuestionsScreenState extends State<SavedChapterQuestionsScreen> {
  late List<Question> _questions;
  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _questions = List.from(widget.chapterGroup.questions);
  }

  Future<void> _unsaveQuestion(Question question) async {
    try {
      final qRepo = context.read<QuestionRepository>();
      await qRepo.removeSavedQuestion(question.questionId, studentId: _studentId);
      if (!mounted) return;

      setState(() {
        _questions.removeWhere((q) => q.questionId == question.questionId);
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Question removed from saved'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.primary,
            onPressed: () async {
              await qRepo.toggleSaveQuestion(question, studentId: _studentId);
              if (mounted) {
                setState(() => _questions.add(question));
              }
            },
          ),
        ),
      );
    } catch (_) {}
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
          mode: 'practice',
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
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 16, color: AppColors.primary),
                      SizedBox(width: 4),
                      Text(
                        'Practise Chapter',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
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
              message: 'All saved questions in this chapter have been removed.',
              icon: Icons.check_circle_outline_rounded,
              actionLabel: 'Back to Chapters',
              onAction: () => Navigator.pop(context),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              itemCount: _questions.length,
              itemBuilder: (ctx, i) {
                final q = _questions[i];
                return _SavedQuestionCard(
                  key: ValueKey(q.questionId),
                  question: q,
                  onUnsave: () => _unsaveQuestion(q),
                  onPractice: () => _startPracticeSession([q]),
                );
              },
            ),
    );
  }
}

class _SavedQuestionCard extends StatelessWidget {
  final Question question;
  final VoidCallback onUnsave;
  final VoidCallback onPractice;

  const _SavedQuestionCard({
    super.key,
    required this.question,
    required this.onUnsave,
    required this.onPractice,
  });

  @override
  Widget build(BuildContext context) {
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
                message: 'Remove bookmark',
                child: BounceTap(
                  onTap: onUnsave,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Icon(
                      Icons.bookmark_rounded,
                      size: 18,
                      color: AppColors.primary,
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
          // Correct Answer Pill
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
                    'Option ${question.correctOptionId}: ${correctOpt.text}',
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: BounceTap(
              onTap: onPractice,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        size: 15, color: AppColors.primary),
                    SizedBox(width: 5),
                    Text(
                      'Practise Question',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
