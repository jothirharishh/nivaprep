// lib/features/progress/progress_screen.dart
// In-depth mastery and diagnostic insights per chapter and subject.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/common_widgets.dart';
import '../../core/networking/api_client.dart';
import '../../data/models/progress.dart';
import '../../data/models/subject.dart';
import '../../data/repositories/progress_repository.dart';
import '../practice/practice_screen.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<SubjectMastery>? _subjectMasteries;
  Map<String, int>? _overallStats;
  bool _loading = true;
  String? _error;

  // Filter & Search state
  String _selectedSubjectFilter = 'all'; // 'all' or subjectId
  String _masteryFilter = 'all'; // 'all', 'needs_practice', 'mastered', 'not_started'
  String _searchQuery = '';
  String _sortBy = 'number'; // 'number', 'mastery_low', 'mastery_high', 'attempts'

  final TextEditingController _searchController = TextEditingController();

  static const _studentId = 'local_anon';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<ProgressRepository>();
      final api = context.read<ApiClient>();

      final stats = await repo.getOverallStats(_studentId);
      final masteries = await repo.getSubjectAndChapterMastery(
        _studentId,
        api: api,
      );

      if (mounted) {
        setState(() {
          _overallStats = stats;
          _subjectMasteries = masteries;
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

  // ── Computed Aggregates ──────────────────────────────────────────────────────

  int get _totalAttempts => _overallStats?['total'] ?? 0;
  int get _correctAttempts => _overallStats?['correct'] ?? 0;
  double get _overallAccuracy =>
      _totalAttempts == 0 ? 0.0 : _correctAttempts / _totalAttempts;

  int get _totalSyllabusChapters =>
      _subjectMasteries?.fold<int>(0, (sum, s) => sum + s.totalChapters) ?? 56;

  int get _totalMasteredChapters =>
      _subjectMasteries?.fold<int>(0, (sum, s) => sum + s.masteredChapters) ?? 0;

  int get _totalActiveMistakes =>
      _subjectMasteries?.fold<int>(0, (sum, s) => sum + s.activeMistakes) ?? 0;

  SubjectMastery? get _currentSubjectMastery {
    if (_selectedSubjectFilter == 'all' || _subjectMasteries == null) return null;
    try {
      return _subjectMasteries!.firstWhere(
        (s) => s.subjectId.toLowerCase() == _selectedSubjectFilter.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  List<ChapterMastery> get _filteredChapters {
    if (_subjectMasteries == null) return [];

    List<ChapterMastery> list = [];
    if (_selectedSubjectFilter == 'all') {
      for (final s in _subjectMasteries!) {
        list.addAll(s.chapters);
      }
    } else {
      final sm = _currentSubjectMastery;
      if (sm != null) list.addAll(sm.chapters);
    }

    // Apply mastery tier filter
    if (_masteryFilter == 'needs_practice') {
      list = list.where((c) => c.masteryLevel == MasteryLevel.needsPractice).toList();
    } else if (_masteryFilter == 'mastered') {
      list = list.where((c) => c.masteryLevel == MasteryLevel.mastered).toList();
    } else if (_masteryFilter == 'not_started') {
      list = list.where((c) => c.masteryLevel == MasteryLevel.notStarted).toList();
    }

    // Apply text search
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((c) {
        final title = c.chapterTitle.toLowerCase();
        final numStr = c.chapterNumber.toString();
        final subName = Subject.getDisplayName(c.subjectId).toLowerCase();
        return title.contains(q) || numStr.contains(q) || subName.contains(q);
      }).toList();
    }

    // Apply sorting
    if (_sortBy == 'mastery_low') {
      list.sort((a, b) {
        if (a.totalAttempts == 0 && b.totalAttempts > 0) return 1;
        if (b.totalAttempts == 0 && a.totalAttempts > 0) return -1;
        return a.accuracy.compareTo(b.accuracy);
      });
    } else if (_sortBy == 'mastery_high') {
      list.sort((a, b) => b.accuracy.compareTo(a.accuracy));
    } else if (_sortBy == 'attempts') {
      list.sort((a, b) => b.totalAttempts.compareTo(a.totalAttempts));
    } else {
      // Syllabus order
      list.sort((a, b) {
        final subCmp = a.subjectId.compareTo(b.subjectId);
        if (subCmp != 0) return subCmp;
        return a.chapterNumber.compareTo(b.chapterNumber);
      });
    }

    return list;
  }

  // ── Action Handlers ──────────────────────────────────────────────────────────

  void _startChapterPractice(ChapterMastery chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PracticeScreen(
          subjectId: chapter.subjectId,
          chapterId: chapter.chapterId,
          chapterTitle: chapter.chapterTitle,
          mode: 'practice',
        ),
      ),
    ).then((_) => _load());
  }

  // ── Build Method ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress & Mastery'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: BounceTap(
              onTap: _load,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingState(message: 'Analyzing syllabus mastery…');
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }

    final chapters = _filteredChapters;
    final currentSubject = _currentSubjectMastery;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: CustomScrollView(
        slivers: [
          // 1. Hero Performance & Readiness Card
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _HeroMasteryBanner(
                totalAttempts: _totalAttempts,
                overallAccuracy: _overallAccuracy,
                totalMastered: _totalMasteredChapters,
                totalSyllabus: _totalSyllabusChapters,
                activeMistakes: _totalActiveMistakes,
              ),
            ),
          ),

          // 2. Subject Filter Tabs
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _SubjectFilterChips(
                selectedSubjectId: _selectedSubjectFilter,
                masteries: _subjectMasteries ?? [],
                onSelect: (subId) {
                  setState(() => _selectedSubjectFilter = subId);
                },
              ),
            ),
          ),

          // 3. Subject Insights Spotlight (Strengths & Needs Attention)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _SubjectSpotlightCard(
                subject: currentSubject,
                onSelectChapter: _startChapterPractice,
              ),
            ),
          ),

          // 4. Search and Filter Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  // Search Input
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            size: 20, color: AppColors.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              hintText: 'Search chapters by name or number…',
                              hintStyle: TextStyle(
                                  fontSize: 13, color: AppColors.textMuted),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 11),
                            ),
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary),
                            onChanged: (val) {
                              setState(() => _searchQuery = val);
                            },
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 16, color: AppColors.textMuted),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Mastery Filter & Sort Row
                  Row(
                    children: [
                      // Mastery Pills
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _FilterPill(
                                label: 'All',
                                isSelected: _masteryFilter == 'all',
                                onTap: () =>
                                    setState(() => _masteryFilter = 'all'),
                              ),
                              const SizedBox(width: 6),
                              _FilterPill(
                                label: 'Needs Focus',
                                isSelected: _masteryFilter == 'needs_practice',
                                color: const Color(0xFFEA580C),
                                onTap: () => setState(
                                    () => _masteryFilter = 'needs_practice'),
                              ),
                              const SizedBox(width: 6),
                              _FilterPill(
                                label: 'Mastered',
                                isSelected: _masteryFilter == 'mastered',
                                color: const Color(0xFF059669),
                                onTap: () => setState(
                                    () => _masteryFilter = 'mastered'),
                              ),
                              const SizedBox(width: 6),
                              _FilterPill(
                                label: 'Not Started',
                                isSelected: _masteryFilter == 'not_started',
                                color: const Color(0xFF64748B),
                                onTap: () => setState(
                                    () => _masteryFilter = 'not_started'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Sort Dropdown
                      PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.sort_rounded,
                                  size: 16, color: AppColors.textSecondary),
                              SizedBox(width: 4),
                              Text(
                                'Sort',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        onSelected: (val) => setState(() => _sortBy = val),
                        itemBuilder: (ctx) => [
                          const PopupMenuItem(
                            value: 'number',
                            child: Text('Syllabus Order (1, 2, 3…)'),
                          ),
                          const PopupMenuItem(
                            value: 'mastery_low',
                            child: Text('Needs Practice First'),
                          ),
                          const PopupMenuItem(
                            value: 'mastery_high',
                            child: Text('Highest Accuracy First'),
                          ),
                          const PopupMenuItem(
                            value: 'attempts',
                            child: Text('Most Questions Practiced'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 5. Section Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Chapter Mastery Breakdown',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Text(
                      '${chapters.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 6. Chapter Cards List
          if (chapters.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: EmptyState(
                  message: _searchQuery.isNotEmpty
                      ? 'No chapters matching "$_searchQuery".'
                      : 'No chapters found with the selected filter.',
                  icon: Icons.filter_alt_off_rounded,
                  actionLabel: 'Reset Filters',
                  onAction: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _masteryFilter = 'all';
                      _selectedSubjectFilter = 'all';
                    });
                  },
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chapter = chapters[index];
                    return _ChapterMasteryTile(
                      chapter: chapter,
                      onPractise: () => _startChapterPractice(chapter),
                    );
                  },
                  childCount: chapters.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ── Hero Mastery Card ─────────────────────────────────────────────────────────

class _HeroMasteryBanner extends StatelessWidget {
  final int totalAttempts;
  final double overallAccuracy;
  final int totalMastered;
  final int totalSyllabus;
  final int activeMistakes;

  const _HeroMasteryBanner({
    required this.totalAttempts,
    required this.overallAccuracy,
    required this.totalMastered,
    required this.totalSyllabus,
    required this.activeMistakes,
  });

  @override
  Widget build(BuildContext context) {
    final progressRatio = totalSyllabus == 0 ? 0.0 : totalMastered / totalSyllabus;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x301E3A8A),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.workspace_premium_rounded,
                        size: 13, color: Color(0xFFFDE047)),
                    SizedBox(width: 4),
                    Text(
                      'BOARD MASTERY MONITOR',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Class 10 Syllabus',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Center Metric Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalMastered / $totalSyllabus',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.0,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalAttempts == 0
                          ? 'Start your first practice to track chapter mastery'
                          : '$totalMastered chapters mastered with ≥85% accuracy',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFFDBEAFE),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Circular Accuracy Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      '${(overallAccuracy * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Accuracy',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFBFDBFE),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Linear Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressRatio,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF34D399)),
            ),
          ),
          const SizedBox(height: 16),

          // Bottom Stats Pills
          Row(
            children: [
              _HeroPill(
                icon: Icons.quiz_rounded,
                label: '$totalAttempts Practised',
                color: const Color(0xFF93C5FD),
              ),
              const SizedBox(width: 8),
              _HeroPill(
                icon: Icons.verified_rounded,
                label: '$totalMastered Mastered',
                color: const Color(0xFF6EE7B7),
              ),
              const SizedBox(width: 8),
              _HeroPill(
                icon: Icons.replay_rounded,
                label: '$activeMistakes to Revise',
                color: activeMistakes > 0
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF6EE7B7),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HeroPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subject Filter Chips ──────────────────────────────────────────────────────

class _SubjectFilterChips extends StatelessWidget {
  final String selectedSubjectId;
  final List<SubjectMastery> masteries;
  final ValueChanged<String> onSelect;

  const _SubjectFilterChips({
    required this.selectedSubjectId,
    required this.masteries,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final totalChapters = masteries.fold(0, (sum, m) => sum + m.totalChapters);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _SubjectChip(
            label: 'All Subjects',
            badge: '$totalChapters',
            isSelected: selectedSubjectId == 'all',
            icon: Icons.dashboard_rounded,
            accentColor: AppColors.primary,
            onTap: () => onSelect('all'),
          ),
          for (final m in masteries) ...[
            const SizedBox(width: 8),
            _SubjectChip(
              label: m.displayName,
              badge: '${m.masteredChapters}/${m.totalChapters}',
              isSelected: selectedSubjectId.toLowerCase() == m.subjectId.toLowerCase(),
              icon: Subject.getIconData(m.subjectId),
              accentColor: Subject.getAccentColor(m.subjectId),
              onTap: () => onSelect(m.subjectId),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubjectChip extends StatelessWidget {
  final String label;
  final String badge;
  final bool isSelected;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _SubjectChip({
    required this.label,
    required this.badge,
    required this.isSelected,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BounceTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColor : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : accentColor,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Subject Spotlight Card ────────────────────────────────────────────────────

class _SubjectSpotlightCard extends StatelessWidget {
  final SubjectMastery? subject;
  final ValueChanged<ChapterMastery> onSelectChapter;

  const _SubjectSpotlightCard({
    required this.subject,
    required this.onSelectChapter,
  });

  @override
  Widget build(BuildContext context) {
    if (subject == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lightbulb_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target 85%+ on each chapter to unlock Mastery',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Filter by subject above to monitor individual unit progress.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final accent = Subject.getAccentColor(subject!.subjectId);
    final strongest = subject!.strongestChapter;
    final weakest = subject!.weakestChapter;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
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
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Subject.getIconData(subject!.subjectId),
                    size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${subject!.displayName} Mastery Overview',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${(subject!.overallAccuracy * 100).toStringAsFixed(1)}% Acc',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Distribution breakdown bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                if (subject!.masteredChapters > 0)
                  Expanded(
                    flex: subject!.masteredChapters,
                    child: Container(
                        height: 6, color: const Color(0xFF059669)),
                  ),
                if (subject!.proficientChapters > 0)
                  Expanded(
                    flex: subject!.proficientChapters,
                    child: Container(
                        height: 6, color: const Color(0xFF2563EB)),
                  ),
                if (subject!.needsPracticeChapters > 0)
                  Expanded(
                    flex: subject!.needsPracticeChapters,
                    child: Container(
                        height: 6, color: const Color(0xFFEA580C)),
                  ),
                if (subject!.notStartedChapters > 0)
                  Expanded(
                    flex: subject!.notStartedChapters,
                    child: Container(
                        height: 6, color: AppColors.surfaceSubtle),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Diagnostic recommendations
          if (strongest != null)
            _InsightRow(
              icon: Icons.star_rounded,
              iconColor: const Color(0xFF059669),
              title: 'Strongest Chapter',
              subtitle:
                  '${strongest.chapterTitle} (${(strongest.accuracy * 100).toStringAsFixed(0)}% accuracy)',
            ),
          if (weakest != null) ...[
            const SizedBox(height: 8),
            _InsightRow(
              icon: Icons.crisis_alert_rounded,
              iconColor: const Color(0xFFEA580C),
              title: 'Recommended Focus',
              subtitle:
                  '${weakest.chapterTitle} · ${weakest.activeMistakes > 0 ? '${weakest.activeMistakes} mistakes to fix' : '${(weakest.accuracy * 100).toStringAsFixed(0)}% accuracy'}',
              actionLabel: 'Practise',
              onAction: () => onSelectChapter(weakest),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _InsightRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: iconColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: iconColor,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            BounceTap(
              onTap: onAction!,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Chapter Mastery Tile ───────────────────────────────────────────────────────

class _ChapterMasteryTile extends StatelessWidget {
  final ChapterMastery chapter;
  final VoidCallback onPractise;

  const _ChapterMasteryTile({
    required this.chapter,
    required this.onPractise,
  });

  @override
  Widget build(BuildContext context) {
    final level = chapter.masteryLevel;
    final accent = Subject.getAccentColor(chapter.subjectId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Number, Title, Status Pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chapter Number Box
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      chapter.chapterNumber.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Chapter Title & Subject Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.chapterTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        Subject.getDisplayName(chapter.subjectId),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Mastery Status Badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: level.bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: level.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(level.icon, size: 12, color: level.color),
                      const SizedBox(width: 4),
                      Text(
                        level.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: level.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Middle: Progress / Accuracy Meter
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    if (chapter.correctAttempts > 0)
                      Expanded(
                        flex: chapter.correctAttempts,
                        child: Container(color: const Color(0xFF059669)),
                      ),
                    if (chapter.incorrectAttempts > 0)
                      Expanded(
                        flex: chapter.incorrectAttempts,
                        child: Container(color: const Color(0xFFEA580C)),
                      ),
                    if (chapter.totalAttempts == 0)
                      Expanded(
                        child: Container(color: AppColors.surfaceSubtle),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Bottom Row: Metrics & Practise Action
            Row(
              children: [
                if (chapter.totalAttempts > 0) ...[
                  Text(
                    '${(chapter.accuracy * 100).toStringAsFixed(0)}% acc (${chapter.correctAttempts}/${chapter.totalAttempts})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (chapter.activeMistakes > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.incorrectLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${chapter.activeMistakes} mistake${chapter.activeMistakes == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppColors.incorrect,
                        ),
                      ),
                    ),
                  ],
                ] else
                  const Text(
                    'Not attempted yet',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                const Spacer(),

                // Direct Practice Button
                BounceTap(
                  onTap: onPractise,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          chapter.totalAttempts > 0
                              ? Icons.replay_rounded
                              : Icons.play_arrow_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          chapter.totalAttempts > 0 ? 'Practise' : 'Start',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
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
      ),
    );
  }
}

// ── Filter Pill ───────────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.isSelected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = color ?? AppColors.primary;

    return BounceTap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.12) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : AppColors.divider,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
