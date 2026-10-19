// lib/features/chapters/chapters_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/networking/api_client.dart';
import '../../data/models/subject.dart';

class ChaptersScreen extends StatefulWidget {
  final Subject subject;
  const ChaptersScreen({super.key, required this.subject});

  @override
  State<ChaptersScreen> createState() => _ChaptersScreenState();
}

class _ChaptersScreenState extends State<ChaptersScreen> {
  List<Chapter>? _chapters;
  String? _error;
  bool _loading = true;

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
      final client = context.read<ApiClient>();
      final chapters = await client.fetchChapters(widget.subject.subjectId);
      if (mounted) {
        setState(() {
          _chapters = chapters;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject.displayName),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const LoadingState(message: 'Loading verified chapters…');
    if (_error != null) return ErrorState(message: _error!, onRetry: _load);
    if (_chapters == null || _chapters!.isEmpty) {
      return const EmptyState(
        message: 'No verified questions available yet.',
        icon: Icons.menu_book_outlined,
      );
    }
    return ListView.builder(
      itemCount: _chapters!.length + 1,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemBuilder: (_, i) {
        if (i == 0) {
          return _SubjectHeaderCard(
            subject: widget.subject,
            chapterCount: _chapters!.length,
          );
        }
        return _ChapterTile(
          chapter: _chapters![i - 1],
          subjectAccent: widget.subject.accentColor,
        );
      },
    );
  }
}

class _SubjectHeaderCard extends StatelessWidget {
  final Subject subject;
  final int chapterCount;

  const _SubjectHeaderCard({
    required this.subject,
    required this.chapterCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: subject.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: subject.accentColor.withValues(alpha: 0.2)),
            ),
            child: Icon(subject.iconData, size: 24, color: subject.accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.displayName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$chapterCount Chapters',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '· 2024–2025 Edition',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  final Chapter chapter;
  final Color subjectAccent;

  const _ChapterTile({
    required this.chapter,
    required this.subjectAccent,
  });

  @override
  Widget build(BuildContext context) {
    final available = chapter.hasContent;
    final hasQuestions = chapter.questionCount > 0;

    final String badgeText;
    final Color badgeBg;
    final Color badgeFg;
    if (hasQuestions) {
      badgeText = '${chapter.questionCount} question${chapter.questionCount == 1 ? '' : 's'}';
      badgeBg = AppColors.correctLight;
      badgeFg = AppColors.correct;
    } else if (available) {
      badgeText = 'Live AI Practice';
      badgeBg = AppColors.primaryLight;
      badgeFg = AppColors.primary;
    } else {
      badgeText = 'Unavailable';
      badgeBg = AppColors.surfaceSubtle;
      badgeFg = AppColors.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BounceTap(
        onTap: available
            ? () => Navigator.pushNamed(context, '/mode-select', arguments: chapter)
            : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: available ? AppColors.divider : AppColors.divider.withValues(alpha: 0.6),
            ),
            boxShadow: available
                ? const [
                    BoxShadow(
                      color: Color(0x050F172A),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: available ? subjectAccent.withValues(alpha: 0.1) : AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    chapter.chapterNumber.toString().padLeft(2, '0'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: available ? subjectAccent : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      chapter.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        color: available ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: badgeFg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (available)
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 11,
                    color: AppColors.textSecondary,
                  ),
                )
              else
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
