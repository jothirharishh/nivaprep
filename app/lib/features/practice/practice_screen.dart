// lib/features/practice/practice_screen.dart
// Core practice quiz with immediate feedback.
// Loads from the verified question bank first; falls back to live RAG generation
// when no verified questions exist for the chapter.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/networking/api_client.dart';
import '../../data/models/question.dart';
import '../../data/repositories/question_repository.dart';
import '../../data/repositories/progress_repository.dart';
import '../results/results_screen.dart';

enum _OptionState { idle, selected, correct, wrong }

class PracticeScreen extends StatefulWidget {
  final String subjectId;
  final String chapterId;
  final String chapterTitle;
  final String mode; // 'practice' | 'exam' | 'mistake_review'
  final List<Question>? initialQuestions;

  const PracticeScreen({
    super.key,
    required this.subjectId,
    required this.chapterId,
    required this.chapterTitle,
    this.mode = 'practice',
    this.initialQuestions,
  });

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  // ── Question state ─────────────────────────────────────────────────────────
  List<Question> _questions = [];
  bool _loading = true;
  String? _error;

  // Live-mode state (used when static bank is empty)
  bool _liveMode = false;
  bool _generatingNext = false;
  String? _liveError;
  Question? _prefetchedQuestion;
  bool _prefetching = false;

  // Track IDs we've already seen in this session to avoid repeats
  final List<String> _seenIds = [];

  // ── Quiz state ─────────────────────────────────────────────────────────────
  int _currentIndex = 0;
  String? _selectedOptionId;
  bool _checked = false;
  final Map<String, String?> _examAnswers = {};
  bool _submitting = false;
  final Map<String, bool> _results = {};
  bool _isCurrentSaved = false;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Future<void> _loadQuestions() async {
    if (widget.initialQuestions != null && widget.initialQuestions!.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _questions = List.from(widget.initialQuestions!);
        _loading = false;
      });
      _checkCurrentSaved();
      return;
    }

    try {
      final repo = context.read<QuestionRepository>();
      final qs = await repo.getQuestionsForChapter(
        widget.subjectId,
        widget.chapterId,
      );

      if (!mounted) return;

      if (qs.isEmpty) {
        // No verified questions in bank → switch to live generation mode
        setState(() {
          _liveMode = true;
          _loading = false;
        });
        await _loadNextLiveQuestion();
      } else {
        setState(() {
          _questions = qs;
          _loading = false;
        });
        _checkCurrentSaved();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _checkCurrentSaved() async {
    if (_questions.isEmpty || _currentIndex >= _questions.length) return;
    try {
      final repo = context.read<QuestionRepository>();
      final saved = await repo.isQuestionSaved(_current.questionId);
      if (mounted) {
        setState(() => _isCurrentSaved = saved);
      }
    } catch (_) {}
  }

  Future<void> _toggleSaveCurrent() async {
    if (_questions.isEmpty || _currentIndex >= _questions.length) return;
    try {
      final repo = context.read<QuestionRepository>();
      final saved = await repo.toggleSaveQuestion(_current);
      if (!mounted) return;
      setState(() => _isCurrentSaved = saved);
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

  Future<void> _loadNextLiveQuestion() async {
    if (!mounted) return;

    // Fast path: if background prefetch has already loaded the next question, use it immediately!
    if (_prefetchedQuestion != null) {
      final q = _prefetchedQuestion!;
      _prefetchedQuestion = null;
      setState(() {
        _questions.add(q);
        _seenIds.add(q.questionId);
        _currentIndex = _questions.length - 1;
        _selectedOptionId = null;
        _checked = false;
        _generatingNext = false;
        _liveError = null;
      });
      _checkCurrentSaved();
      _prefetchNextLiveQuestion();
      return;
    }

    setState(() {
      _generatingNext = true;
      _liveError = null;
    });

    try {
      final repo = context.read<QuestionRepository>();
      final q = await repo.generateLiveQuestion(
        subjectId: widget.subjectId,
        chapterId: widget.chapterId,
        alreadySeen: List.from(_seenIds),
      );

      if (!mounted) return;
      setState(() {
        _questions.add(q);
        _seenIds.add(q.questionId);
        _currentIndex = _questions.length - 1;
        _selectedOptionId = null;
        _checked = false;
        _generatingNext = false;
      });
      _checkCurrentSaved();
      // Start background prefetch for the following question while student works on this one
      _prefetchNextLiveQuestion();
    } on LiveGenerationUnavailableException catch (e) {
      if (!mounted) return;
      setState(() {
        _generatingNext = false;
        _liveError = 'Live questions are not available yet.\n'
            'The textbook index needs to be built first.\n\n'
            'Details: ${e.message}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generatingNext = false;
        _liveError = 'Could not generate a question: $e\nTap retry to try again.';
      });
    }
  }

  /// Asynchronously pre-fetch the next live question while student reads/answers current question.
  Future<void> _prefetchNextLiveQuestion() async {
    if (!_liveMode || _prefetching || _prefetchedQuestion != null || !mounted) return;
    _prefetching = true;
    try {
      final repo = context.read<QuestionRepository>();
      final alreadySeen = List<String>.from(_seenIds);
      final q = await repo.generateLiveQuestion(
        subjectId: widget.subjectId,
        chapterId: widget.chapterId,
        alreadySeen: alreadySeen,
      );
      if (mounted) {
        setState(() {
          _prefetchedQuestion = q;
        });
      }
    } catch (_) {
      // Non-fatal background prefetch failure; _loadNextLiveQuestion will retry normally on tap
    } finally {
      _prefetching = false;
    }
  }

  // ── Quiz helpers ───────────────────────────────────────────────────────────

  Question get _current => _questions[_currentIndex];
  bool get _isPractice => widget.mode == 'practice';
  bool get _hasQuestions => _questions.isNotEmpty;

  void _selectOption(String optionId) {
    if (_checked) return;
    setState(() {
      _selectedOptionId = optionId;
      if (!_isPractice) _examAnswers[_current.questionId] = optionId;
    });
  }

  Future<void> _checkAnswer() async {
    if (_selectedOptionId == null || _checked || _submitting) return;
    setState(() {
      _submitting = true;
      _checked = true;
    });
    final isCorrect = _selectedOptionId == _current.correctOptionId;
    _results[_current.questionId] = isCorrect;

    final qRepo = context.read<QuestionRepository>();
    final progress = context.read<ProgressRepository>();

    try {
      // Ensure question is cached so it is available for mistake vault and offline review
      await qRepo.cacheQuestion(_current);

      const studentId = 'local_anon';
      await progress.recordAttempt(
        localStudentId: studentId,
        questionId: _current.questionId,
        subjectId: widget.subjectId,
        chapterId: widget.chapterId,
        selectedOptionId: _selectedOptionId,
        isCorrect: isCorrect,
        mode: widget.mode,
        questionContentVersion: _current.contentVersion,
      );
    } catch (_) {
      // Non-fatal — continue practice
    }
    setState(() => _submitting = false);
  }

  void _next() {
    if (_liveMode) {
      // In live mode: generate a fresh question instead of advancing an index
      _loadNextLiveQuestion();
      return;
    }
    final isLast = _currentIndex == _questions.length - 1;
    if (isLast) {
      _showResults();
      return;
    }
    setState(() {
      _currentIndex++;
      _selectedOptionId = null;
      _checked = false;
    });
    _checkCurrentSaved();
  }

  void _showResults() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(
          questions: _questions,
          results: _results,
          chapterTitle: widget.chapterTitle,
        ),
      ),
    );
  }

  Future<void> _submitExam() async {
    final progress = context.read<ProgressRepository>();
    final qRepo = context.read<QuestionRepository>();
    const studentId = 'local_anon';

    for (final q in _questions) {
      final sel = _examAnswers[q.questionId];
      final isCorrect = sel == q.correctOptionId;
      _results[q.questionId] = isCorrect;
      try {
        await qRepo.cacheQuestion(q);
        await progress.recordAttempt(
          localStudentId: studentId,
          questionId: q.questionId,
          subjectId: widget.subjectId,
          chapterId: widget.chapterId,
          selectedOptionId: sel,
          isCorrect: isCorrect,
          mode: widget.mode,
          questionContentVersion: q.contentVersion,
        );
      } catch (_) {}
    }
    _showResults();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Initial load spinner
    if (_loading) {
      return const Scaffold(body: LoadingState(message: 'Loading questions…'));
    }

    // Hard error (network/parse failure on initial load)
    if (_error != null) return Scaffold(body: ErrorState(message: _error!));

    // Live mode: generating first question
    if (_liveMode && !_hasQuestions && _generatingNext) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chapterTitle)),
        body: const LoadingState(message: 'Generating question from textbook…'),
      );
    }

    // Live mode: generation failed before any question loaded
    if (_liveMode && !_hasQuestions && _liveError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.chapterTitle)),
        body: _LiveErrorState(
          message: _liveError!,
          onRetry: _loadNextLiveQuestion,
        ),
      );
    }

    // Static mode: no verified questions, no live fallback
    if (!_hasQuestions) {
      return const Scaffold(
        body: EmptyState(
          message: 'No verified questions available yet.',
          icon: Icons.quiz_outlined,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        bottom: !_liveMode
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_currentIndex + 1) / _questions.length,
                    backgroundColor: AppColors.divider,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                ),
              )
            : null,
        actions: [
          if (_liveMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded,
                        size: 13, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      'Live AI',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_isPractice && !_liveMode)
            TextButton(
              onPressed: _submitExam,
              child: const Text('Submit'),
            ),
        ],
      ),
      body: _generatingNext
          ? const LoadingState(message: 'Generating next question from textbook…')
          : _QuizBody(
              question: _current,
              questionNumber: _currentIndex + 1,
              total: _liveMode ? null : _questions.length,
              selectedOptionId: _selectedOptionId,
              checked: _checked,
              isPractice: _isPractice,
              isLiveMode: _liveMode,
              isSaved: _isCurrentSaved,
              onToggleSave: _toggleSaveCurrent,
              isLastQuestion: !_liveMode && _currentIndex == _questions.length - 1,
              onSelectOption: _selectOption,
              onCheck: _checkAnswer,
              onNext: _next,
              liveError: _liveError,
              onRetryLive: _liveError != null ? _loadNextLiveQuestion : null,
            ),
    );
  }
}

// ── Quiz body ────────────────────────────────────────────────────────────────

class _QuizBody extends StatelessWidget {
  final Question question;
  final int questionNumber;
  final int? total; // null in live mode (endless)
  final String? selectedOptionId;
  final bool checked;
  final bool isPractice;
  final bool isLiveMode;
  final bool isSaved;
  final VoidCallback onToggleSave;
  final ValueChanged<String> onSelectOption;
  final VoidCallback onCheck;
  final VoidCallback onNext;
  final bool isLastQuestion;
  final String? liveError;
  final VoidCallback? onRetryLive;

  const _QuizBody({
    required this.question,
    required this.questionNumber,
    required this.total,
    required this.selectedOptionId,
    required this.checked,
    required this.isPractice,
    required this.isLiveMode,
    required this.isSaved,
    required this.onToggleSave,
    required this.onSelectOption,
    required this.onCheck,
    required this.onNext,
    required this.isLastQuestion,
    this.liveError,
    this.onRetryLive,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x060F172A),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        total != null
                            ? 'Q ${questionNumber.toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}'
                            : 'Question $questionNumber',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const Spacer(),
                    OriginBadge(origin: question.origin),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: isSaved ? 'Remove from saved' : 'Save question',
                      child: BounceTap(
                        onTap: onToggleSave,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: isSaved
                                ? AppColors.primaryLight
                                : AppColors.surfaceSubtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSaved
                                  ? const Color(0xFFBFDBFE)
                                  : AppColors.divider,
                            ),
                          ),
                          child: Icon(
                            isSaved
                                ? Icons.bookmark_rounded
                                : Icons.bookmark_border_rounded,
                            size: 18,
                            color: isSaved
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  question.questionText,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    letterSpacing: -0.2,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Options section
          ...question.options.map(
            (opt) => _OptionTile(
              option: opt,
              state: _stateFor(opt.optionId),
              onTap: checked ? null : () => onSelectOption(opt.optionId),
            ),
          ),
          const SizedBox(height: 16),

          // Feedback panel
          if (isPractice && checked) ...[
            _FeedbackPanel(question: question),
            const SizedBox(height: 18),
          ],

          // Actions
          if (isPractice) ...[
            if (!checked)
              BounceTap(
                onTap: selectedOptionId != null ? onCheck : null,
                child: ElevatedButton(
                  onPressed: selectedOptionId != null ? onCheck : null,
                  child: const Text('Check answer'),
                ),
              )
            else
              BounceTap(
                onTap: onNext,
                child: ElevatedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(
                    isLiveMode
                        ? 'Next question'
                        : (isLastQuestion ? 'View results' : 'Next question'),
                  ),
                ),
              ),
          ],

          // Live-mode error after first question has loaded
          if (liveError != null) ...[
            const SizedBox(height: 16),
            _LiveErrorState(message: liveError!, onRetry: onRetryLive),
          ],
        ],
      ),
    );
  }

  _OptionState _stateFor(String optionId) {
    if (!checked) {
      return selectedOptionId == optionId
          ? _OptionState.selected
          : _OptionState.idle;
    }
    if (optionId == question.correctOptionId) return _OptionState.correct;
    if (optionId == selectedOptionId) return _OptionState.wrong;
    return _OptionState.idle;
  }
}

// ── Option tile ──────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final QuestionOption option;
  final _OptionState state;
  final VoidCallback? onTap;

  const _OptionTile({required this.option, required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (bg, border, textColor, badgeBg, badgeFg) = switch (state) {
      _OptionState.correct => (
          AppColors.correctLight,
          AppColors.correct,
          AppColors.textPrimary,
          AppColors.correct,
          Colors.white,
        ),
      _OptionState.wrong => (
          AppColors.incorrectLight,
          AppColors.incorrect,
          AppColors.textPrimary,
          AppColors.incorrect,
          Colors.white,
        ),
      _OptionState.selected => (
          AppColors.primaryLight,
          AppColors.primary,
          AppColors.textPrimary,
          AppColors.primary,
          Colors.white,
        ),
      _OptionState.idle => (
          AppColors.surface,
          AppColors.divider,
          AppColors.textPrimary,
          AppColors.surfaceSubtle,
          AppColors.textSecondary,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BounceTap(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(
              color: border,
              width: state == _OptionState.idle ? 1.0 : 1.5,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x040F172A),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    option.optionId,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: badgeFg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  option.text,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                    height: 1.4,
                  ),
                ),
              ),
              if (state == _OptionState.correct)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.correct, size: 22),
              if (state == _OptionState.wrong)
                const Icon(Icons.cancel_rounded,
                    color: AppColors.incorrect, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Feedback panel ────────────────────────────────────────────────────────────

class _FeedbackPanel extends StatelessWidget {
  final Question question;
  const _FeedbackPanel({required this.question});

  @override
  Widget build(BuildContext context) {
    final correctOpt = question.options.firstWhere(
      (o) => o.optionId == question.correctOptionId,
      orElse: () => QuestionOption(optionId: question.correctOptionId, text: ''),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Correct Answer Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.correctLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.correctBorder),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.correct,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Correct Answer: Option ${question.correctOptionId}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.correct,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (correctOpt.text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          correctOpt.text,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Detailed Explanation Section
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 15,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'WHY THIS IS CORRECT',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            question.explanation,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              fontWeight: FontWeight.w400,
              color: AppColors.textPrimary,
            ),
          ),
          if (question.sourceRefs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'TEXTBOOK REFERENCE',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 6),
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
        ],
      ),
    );
  }
}

// ── Live error widget ─────────────────────────────────────────────────────────

class _LiveErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _LiveErrorState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.incorrectLight,
        border: Border.all(color: AppColors.incorrectBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.incorrect, size: 18),
            SizedBox(width: 8),
            Text(
              'Could not generate question',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.incorrect,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppColors.textSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            BounceTap(
              onTap: onRetry,
              child: OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
