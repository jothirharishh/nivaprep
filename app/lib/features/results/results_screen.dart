// lib/features/results/results_screen.dart

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/question.dart';
import '../../core/widgets/common_widgets.dart';

class ResultsScreen extends StatelessWidget {
  final List<Question> questions;
  final Map<String, bool> results; // question_id → is_correct
  final String chapterTitle;

  const ResultsScreen({
    super.key,
    required this.questions,
    required this.results,
    required this.chapterTitle,
  });

  int get _correct => results.values.where((v) => v).length;
  int get _incorrect => results.values.where((v) => !v).length;
  int get _unanswered => questions.length - results.length;
  double get _pct => questions.isEmpty ? 0 : _correct / questions.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Results'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            _ScoreCard(
              correct: _correct,
              total: questions.length,
              percent: _pct,
            ),
            const SizedBox(height: 16),
            _StatsRow(
              correct: _correct,
              incorrect: _incorrect,
              unanswered: _unanswered,
            ),
            const SizedBox(height: 24),
            BounceTap(
              onTap: () => _showAnswerReview(context),
              child: OutlinedButton.icon(
                onPressed: () => _showAnswerReview(context),
                icon: const Icon(Icons.list_alt_rounded, size: 18),
                label: const Text('Review answers'),
              ),
            ),
            const SizedBox(height: 12),
            BounceTap(
              onTap: () =>
                  Navigator.popUntil(context, ModalRoute.withName('/')),
              child: ElevatedButton.icon(
                onPressed: () =>
                    Navigator.popUntil(context, ModalRoute.withName('/')),
                icon: const Icon(Icons.home_rounded, size: 18),
                label: const Text('Back to Home'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAnswerReview(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _AnswerReviewScreen(questions: questions, results: results),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int correct;
  final int total;
  final double percent;

  const _ScoreCard({
    required this.correct,
    required this.total,
    required this.percent,
  });

  (IconData, Color, String) get _badgeData {
    if (percent >= 0.9) {
      return (
        Icons.workspace_premium_rounded,
        const Color(0xFFF59E0B),
        'Mastery achieved',
      );
    }
    if (percent >= 0.7) {
      return (
        Icons.verified_rounded,
        const Color(0xFF60A5FA),
        'Solid textbook foundation',
      );
    }
    if (percent >= 0.5) {
      return (
        Icons.trending_up_rounded,
        const Color(0xFF34D399),
        'Good progress — keep going',
      );
    }
    return (
      Icons.auto_stories_rounded,
      const Color(0xFF94A3B8),
      'Practise makes permanent',
    );
  }

  @override
  Widget build(BuildContext context) {
    final (badgeIcon, badgeColor, message) = _badgeData;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x202563EB),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(badgeIcon, size: 28, color: badgeColor),
          ),
          const SizedBox(height: 14),
          Text(
            '${(percent * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$correct of $total answered correctly',
              style: const TextStyle(
                color: Color(0xFFDBEAFE),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final int correct;
  final int incorrect;
  final int unanswered;

  const _StatsRow({
    required this.correct,
    required this.incorrect,
    required this.unanswered,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatChip(
          label: 'Correct',
          value: correct,
          color: AppColors.correct,
          bgColor: AppColors.correctLight,
          borderColor: AppColors.correctBorder,
        ),
        const SizedBox(width: 10),
        _StatChip(
          label: 'Incorrect',
          value: incorrect,
          color: AppColors.incorrect,
          bgColor: AppColors.incorrectLight,
          borderColor: AppColors.incorrectBorder,
        ),
        if (unanswered > 0) ...[
          const SizedBox(width: 10),
          _StatChip(
            label: 'Skipped',
            value: unanswered,
            color: AppColors.textSecondary,
            bgColor: AppColors.surfaceSubtle,
            borderColor: AppColors.divider,
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerReviewScreen extends StatelessWidget {
  final List<Question> questions;
  final Map<String, bool> results;

  const _AnswerReviewScreen({required this.questions, required this.results});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Answer Review')),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: questions.length,
        itemBuilder: (_, i) {
          final q = questions[i];
          final isCorrect = results[q.questionId] ?? false;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
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
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? AppColors.correctLight
                            : AppColors.incorrectLight,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isCorrect
                              ? AppColors.correctBorder
                              : AppColors.incorrectBorder,
                        ),
                      ),
                      child: Icon(
                        isCorrect
                            ? Icons.check_rounded
                            : Icons.close_rounded,
                        color: isCorrect
                            ? AppColors.correct
                            : AppColors.incorrect,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Question ${i + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    OriginBadge(origin: q.origin),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  q.questionText,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.correctLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.correctBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 14, color: AppColors.correct),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          q.options
                              .firstWhere((o) => o.optionId == q.correctOptionId)
                              .text,
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
                if (q.explanation.isNotEmpty) ...[
                  const SizedBox(height: 10),
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
                              'EXPLANATION & CONCEPT',
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
                          q.explanation,
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
                if (q.sourceRefs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: q.sourceRefs
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
        },
      ),
    );
  }
}
