// lib/features/home/home_screen.dart
// Bento 2.0 architecture with asymmetric hero, tactile feedback, and calibrated colors

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/models/subject.dart';
import '../../data/repositories/progress_repository.dart';
import '../../data/repositories/question_repository.dart';
import '../../main.dart';
import '../subjects/subject_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Icon(
                Icons.auto_stories_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BoardMate 10',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Samacheer Kalvi Edition',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: BounceTap(
              onTap: () => Navigator.pushNamed(context, '/settings'),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<SubjectProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const LoadingState(message: 'Loading syllabus subjects…');
          }
          if (provider.error != null) {
            return ErrorState(
              message: provider.isOffline
                  ? "You're offline. You can continue with downloaded questions."
                  : "Couldn't load content. Try again or practise saved questions.",
              onRetry: provider.reload,
            );
          }
          return _HomeContent(subjects: provider.subjects);
        },
      ),
    );
  }
}

class _HomeContent extends StatelessWidget {
  final List<Subject> subjects;
  const _HomeContent({required this.subjects});

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _AsymmetricHeroBanner(
              firstSubject: subjects.isNotEmpty ? subjects.first : null,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: _BentoHighlightsRow(subjects: subjects),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              children: [
                Text(
                  'Subjects',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Text(
                    '${subjects.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  '100% Textbook Verified',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.correct,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (subjects.isEmpty)
          const SliverToBoxAdapter(
            child: EmptyState(
              message:
                  'No subjects available yet.\nAdd textbook content to get started.',
              icon: Icons.school_outlined,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _SubjectCard(subject: subjects[i]),
                childCount: subjects.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _AsymmetricHeroBanner extends StatelessWidget {
  final Subject? firstSubject;
  const _AsymmetricHeroBanner({this.firstSubject});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x242563EB),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, size: 12, color: Colors.white),
                    SizedBox(width: 5),
                    Text(
                      'BOARD EXAM PREPARATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Master One-Mark Questions',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Textbook-grounded practice with strict evidence verification for Tamil Nadu Class 10.',
            style: TextStyle(
              color: Color(0xFFDBEAFE),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              BounceTap(
                onTap: () {
                  if (firstSubject != null) {
                    Navigator.pushNamed(
                      context,
                      '/chapters',
                      arguments: firstSubject,
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x18000000),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Start Practising',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: AppColors.primary),
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

class _BentoHighlightsRow extends StatefulWidget {
  final List<Subject> subjects;
  const _BentoHighlightsRow({required this.subjects});

  @override
  State<_BentoHighlightsRow> createState() => _BentoHighlightsRowState();
}

class _BentoHighlightsRowState extends State<_BentoHighlightsRow> {
  int _savedCount = 0;
  int _mistakeCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    try {
      final qRepo = context.read<QuestionRepository>();
      final prog = context.read<ProgressRepository>();
      final saved = await qRepo.getSavedCount();
      final mistakes = await prog.getActiveMistakeCount('local_anon');
      if (mounted) {
        setState(() {
          _savedCount = saved;
          _mistakeCount = mistakes;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _BentoQuickTile(
            title: 'Saved Questions',
            subtitle: _savedCount > 0 ? '$_savedCount bookmarked' : 'Bookmark tricky Qs',
            icon: Icons.bookmark_rounded,
            accentColor: AppColors.primary,
            backgroundColor: AppColors.primaryLight,
            onTap: () async {
              final scope = MainShellScope.of(context);
              if (scope != null) {
                scope.selectTab(1);
              } else {
                await Navigator.pushNamed(context, '/saved');
                _fetchCounts();
              }
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _BentoQuickTile(
            title: 'Mistake Vault',
            subtitle: _mistakeCount > 0 ? '$_mistakeCount to resolve' : 'Target weak spots',
            icon: Icons.replay_rounded,
            accentColor: AppColors.incorrect,
            backgroundColor: AppColors.incorrectLight,
            onTap: () async {
              final scope = MainShellScope.of(context);
              if (scope != null) {
                scope.selectTab(2);
              } else {
                await Navigator.pushNamed(context, '/mistakes');
                _fetchCounts();
              }
            },
          ),
        ),
      ],
    );
  }
}

class _BentoQuickTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _BentoQuickTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BounceTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: accentColor),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final Subject subject;
  const _SubjectCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final accent = subject.accentColor;
    final surfaceTint = subject.surfaceColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BounceTap(
        onTap: () => Navigator.pushNamed(
          context,
          '/chapters',
          arguments: subject,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                color: Color(0x060F172A),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: surfaceTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Icon(
                  subject.iconData,
                  size: 24,
                  color: accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Official Textbook Syllabus',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

