// lib/data/models/subject.dart

import 'package:flutter/material.dart';
import 'question.dart';

class Subject {
  final String subjectId;
  final String displayName;

  const Subject({required this.subjectId, required this.displayName});

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        subjectId: json['subject_id'] as String,
        displayName: json['display_name'] as String,
      );

  static String getDisplayName(String subjectId) {
    switch (subjectId.toLowerCase()) {
      case 'tamil':
        return 'Tamil';
      case 'english':
        return 'English';
      case 'mathematics':
      case 'maths':
        return 'Mathematics';
      case 'science':
        return 'Science';
      case 'social_science':
      case 'social':
        return 'Social Science';
      default:
        if (subjectId.isEmpty) return 'General';
        return subjectId
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
            .join(' ');
    }
  }

  static IconData getIconData(String subjectId) {
    switch (subjectId.toLowerCase()) {
      case 'tamil':
        return Icons.translate_rounded;
      case 'english':
        return Icons.auto_stories_rounded;
      case 'mathematics':
      case 'maths':
        return Icons.functions_rounded;
      case 'science':
        return Icons.biotech_rounded;
      case 'social_science':
      case 'social':
        return Icons.public_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  static Color getAccentColor(String subjectId) {
    switch (subjectId.toLowerCase()) {
      case 'tamil':
        return const Color(0xFFE11D48);
      case 'english':
        return const Color(0xFFD97706);
      case 'mathematics':
      case 'maths':
        return const Color(0xFF4F46E5);
      case 'science':
        return const Color(0xFF059669);
      case 'social_science':
      case 'social':
        return const Color(0xFF0284C7);
      default:
        return const Color(0xFF2563EB);
    }
  }

  static Color getSurfaceColor(String subjectId) {
    switch (subjectId.toLowerCase()) {
      case 'tamil':
        return const Color(0xFFFFF1F2);
      case 'english':
        return const Color(0xFFFFFBEB);
      case 'mathematics':
      case 'maths':
        return const Color(0xFFEEF2FF);
      case 'science':
        return const Color(0xFFECFDF5);
      case 'social_science':
      case 'social':
        return const Color(0xFFF0F9FF);
      default:
        return const Color(0xFFEFF6FF);
    }
  }

  String get icon {
    switch (subjectId) {
      case 'tamil':
        return '🔤';
      case 'english':
        return '📖';
      case 'mathematics':
        return '📐';
      case 'science':
        return '🔬';
      case 'social_science':
        return '🌏';
      default:
        return '📚';
    }
  }

  IconData get iconData => getIconData(subjectId);
  Color get accentColor => getAccentColor(subjectId);
  Color get surfaceColor => getSurfaceColor(subjectId);
}

class Chapter {
  final String chapterId;
  final String sourceId;
  final String subjectId;
  final int chapterNumber;
  final String title;
  final String status;
  final int questionCount;

  const Chapter({
    required this.chapterId,
    required this.sourceId,
    required this.subjectId,
    required this.chapterNumber,
    required this.title,
    required this.status,
    this.questionCount = 0,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        chapterId: json['chapter_id'] as String,
        sourceId: (json['source_id'] ?? '') as String,
        subjectId: json['subject_id'] as String,
        chapterNumber: (json['chapter_number'] ?? 0) as int,
        title: json['title'] as String,
        status: (json['status'] ?? 'pending') as String,
        questionCount: (json['question_count'] ?? 0) as int,
      );

  bool get hasContent =>
      questionCount > 0 ||
      status == 'ready' ||
      status == 'reviewed' ||
      status == 'completed';
}

class ChapterGroup {
  final String chapterId;
  final String chapterTitle;
  final List<Question> questions;

  const ChapterGroup({
    required this.chapterId,
    required this.chapterTitle,
    required this.questions,
  });
}

class SubjectGroup {
  final String subjectId;
  final String subjectTitle;
  final List<ChapterGroup> chapters;

  const SubjectGroup({
    required this.subjectId,
    required this.subjectTitle,
    required this.chapters,
  });

  int get totalQuestions =>
      chapters.fold(0, (sum, ch) => sum + ch.questions.length);

  static List<SubjectGroup> groupQuestions(List<Question> questions) {
    if (questions.isEmpty) return [];

    final Map<String, Map<String, List<Question>>> tree = {};
    final Map<String, String> chapterTitles = {};

    for (final q in questions) {
      final subId = q.subjectId.trim().isNotEmpty ? q.subjectId.trim() : 'general';
      final chId = q.chapterId.trim().isNotEmpty ? q.chapterId.trim() : 'general_ch';
      final chTitle = q.chapterTitle.trim().isNotEmpty ? q.chapterTitle.trim() : 'General Revision';

      tree.putIfAbsent(subId, () => {});
      tree[subId]!.putIfAbsent(chId, () => []);
      tree[subId]![chId]!.add(q);
      chapterTitles[chId] = chTitle;
    }

    final List<SubjectGroup> result = [];
    for (final subEntry in tree.entries) {
      final subId = subEntry.key;
      final List<ChapterGroup> chapters = [];
      for (final chEntry in subEntry.value.entries) {
        chapters.add(ChapterGroup(
          chapterId: chEntry.key,
          chapterTitle: chapterTitles[chEntry.key] ?? chEntry.key,
          questions: chEntry.value,
        ));
      }
      result.add(SubjectGroup(
        subjectId: subId,
        subjectTitle: Subject.getDisplayName(subId),
        chapters: chapters,
      ));
    }

    const subjectOrder = [
      'tamil',
      'english',
      'mathematics',
      'maths',
      'science',
      'social_science',
      'social'
    ];
    result.sort((a, b) {
      final aIdx = subjectOrder.indexOf(a.subjectId.toLowerCase());
      final bIdx = subjectOrder.indexOf(b.subjectId.toLowerCase());
      if (aIdx != -1 && bIdx != -1) return aIdx.compareTo(bIdx);
      if (aIdx != -1) return -1;
      if (bIdx != -1) return 1;
      return a.subjectTitle.compareTo(b.subjectTitle);
    });

    return result;
  }
}

/// Official Tamil Nadu Samacheer Kalvi Class 10 Textbook Syllabus Catalog.
/// Provides canonical chapter listings across all 5 subjects with offline resilience.
class CanonicalSyllabus {
  static const Map<String, List<Map<String, dynamic>>> data = {
    'tamil': [
      {'id': 'tam_ch01', 'num': 1, 'title': 'இயல் 1: அமுதஊற்று — அன்னை மொழியே / தமிழ்ச்சொல் வளம்'},
      {'id': 'tam_ch02', 'num': 2, 'title': 'இயல் 2: உயிரின் ஓசை — கேட்கிறதா என் குரல்! / பரிபாடல்'},
      {'id': 'tam_ch03', 'num': 3, 'title': 'இயல் 3: கூட்டாஞ்சோறு — விருந்து போற்றுதும்! / காசிக்காண்டம்'},
      {'id': 'tam_ch04', 'num': 4, 'title': 'இயல் 4: மணற்கேணி — மொழிபெயர்ப்புக் கல்வி / திருவிளையாடற் புராணம்'},
      {'id': 'tam_ch05', 'num': 5, 'title': 'இயல் 5: நிலா முற்றம் — பன்முகக் கலைஞர் / கம்பராமாயணம்'},
      {'id': 'tam_ch06', 'num': 6, 'title': 'இயல் 6: விதை நெல் — சிற்றகல் ஒளி / சிலப்பதிகாரம்'},
      {'id': 'tam_ch07', 'num': 7, 'title': 'இயல் 7: பெருவழி — சங்க இலக்கியத்தில் அறம் / தேம்பாவணி'},
    ],
    'english': [
      {'id': 'eng_u01', 'num': 1, 'title': 'Unit 1: His First Flight'},
      {'id': 'eng_u02', 'num': 2, 'title': 'Unit 2: The Night the Ghost Got In'},
      {'id': 'eng_u03', 'num': 3, 'title': 'Unit 3: Empowered Women Navigating the World'},
      {'id': 'eng_u04', 'num': 4, 'title': 'Unit 4: The Attic'},
      {'id': 'eng_u05', 'num': 5, 'title': 'Unit 5: Tech Bloomers'},
      {'id': 'eng_u06', 'num': 6, 'title': 'Unit 6: The Last Lesson'},
      {'id': 'eng_u07', 'num': 7, 'title': 'Unit 7: The Dying Detective'},
    ],
    'mathematics': [
      {'id': 'mat_ch01', 'num': 1, 'title': 'Relations and Functions'},
      {'id': 'mat_ch02', 'num': 2, 'title': 'Numbers and Sequences'},
      {'id': 'mat_ch03', 'num': 3, 'title': 'Algebra'},
      {'id': 'mat_ch04', 'num': 4, 'title': 'Geometry'},
      {'id': 'mat_ch05', 'num': 5, 'title': 'Coordinate Geometry'},
      {'id': 'mat_ch06', 'num': 6, 'title': 'Trigonometry'},
      {'id': 'mat_ch07', 'num': 7, 'title': 'Mensuration'},
      {'id': 'mat_ch08', 'num': 8, 'title': 'Statistics and Probability'},
    ],
    'science': [
      {'id': 'sci_ch01', 'num': 1, 'title': 'Laws of Motion'},
      {'id': 'sci_ch02', 'num': 2, 'title': 'Optics'},
      {'id': 'sci_ch03', 'num': 3, 'title': 'Thermal Physics'},
      {'id': 'sci_ch04', 'num': 4, 'title': 'Electricity'},
      {'id': 'sci_ch05', 'num': 5, 'title': 'Acoustics'},
      {'id': 'sci_ch06', 'num': 6, 'title': 'Nuclear Physics'},
      {'id': 'sci_ch07', 'num': 7, 'title': 'Atoms and Molecules'},
      {'id': 'sci_ch08', 'num': 8, 'title': 'Periodic Classification of Elements'},
      {'id': 'sci_ch09', 'num': 9, 'title': 'Solutions'},
      {'id': 'sci_ch10', 'num': 10, 'title': 'Types of Chemical Reactions'},
      {'id': 'sci_ch11', 'num': 11, 'title': 'Carbon and its Compounds'},
      {'id': 'sci_ch12', 'num': 12, 'title': 'Plant Anatomy and Plant Physiology'},
      {'id': 'sci_ch13', 'num': 13, 'title': 'Structural Organisation of Animals'},
      {'id': 'sci_ch14', 'num': 14, 'title': 'Transportation in Plants and Circulation in Animals'},
      {'id': 'sci_ch15', 'num': 15, 'title': 'Nervous System'},
      {'id': 'sci_ch16', 'num': 16, 'title': 'Plant and Animal Hormones'},
      {'id': 'sci_ch17', 'num': 17, 'title': 'Reproduction in Plants and Animals'},
      {'id': 'sci_ch18', 'num': 18, 'title': 'Genetics'},
      {'id': 'sci_ch19', 'num': 19, 'title': 'Origin and Evolution of Life'},
      {'id': 'sci_ch20', 'num': 20, 'title': 'Breeding and Biotechnology'},
      {'id': 'sci_ch21', 'num': 21, 'title': 'Health and Diseases'},
      {'id': 'sci_ch22', 'num': 22, 'title': 'Environmental Management'},
      {'id': 'sci_ch23', 'num': 23, 'title': 'Visual Communication'},
    ],
    'social_science': [
      {'id': 'soc_his_01', 'num': 1, 'title': 'History Unit 1: Outbreak of World War I'},
      {'id': 'soc_geo_01', 'num': 2, 'title': 'Geography Unit 1: India - Location, Relief and Drainage'},
      {'id': 'src_tn_soc_10_2025_civ_04', 'num': 4, 'title': 'Civics Unit 4: India’s Foreign Policy'},
      {'id': 'src_tn_soc_10_2025_eco_04', 'num': 4, 'title': 'Economics Unit 4: Government and Taxes'},
      {'id': 'src_tn_soc_10_2025_geo_05', 'num': 5, 'title': 'Geography Unit 5: India - Population, Transport, Communication and Trade'},
      {'id': 'src_tn_soc_10_2025_civ_05', 'num': 5, 'title': 'Civics Unit 5: India’s International Relations'},
      {'id': 'src_tn_soc_10_2025_eco_05', 'num': 5, 'title': 'Economics Unit 5: Industrial Clusters in Tamil Nadu'},
      {'id': 'src_tn_soc_10_2025_geo_07', 'num': 7, 'title': 'Geography Unit 7: Human Geography of Tamil Nadu'},
      {'id': 'src_tn_soc_10_2025_his_08', 'num': 8, 'title': 'History Unit 8: Nationalism: Gandhian Phase'},
      {'id': 'src_tn_soc_10_2025_his_09', 'num': 9, 'title': 'History Unit 9: Freedom Struggle in Tamil Nadu'},
      {'id': 'src_tn_soc_10_2025_his_10', 'num': 10, 'title': 'History Unit 10: Social Transformation in Tamil Nadu'},
    ],
  };

  static List<Chapter> getChapters(String subjectId) {
    final sub = subjectId.toLowerCase().trim();
    final items = data[sub] ?? [];
    return items.map((raw) => Chapter(
      chapterId: raw['id'] as String,
      sourceId: 'canonical_$sub',
      subjectId: sub,
      chapterNumber: raw['num'] as int,
      title: raw['title'] as String,
      status: 'ready',
      questionCount: 0,
    )).toList();
  }

  static List<Chapter> getAllChapters() {
    final list = <Chapter>[];
    for (final s in ['tamil', 'english', 'mathematics', 'science', 'social_science']) {
      list.addAll(getChapters(s));
    }
    return list;
  }
}

