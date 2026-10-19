import 'package:flutter_test/flutter_test.dart';
import 'package:boardmate10/data/models/progress.dart';
import 'package:boardmate10/data/models/subject.dart';

void main() {
  group('Canonical Syllabus', () {
    test('contains all 5 Class 10 subjects with canonical chapters', () {
      final tamil = CanonicalSyllabus.getChapters('tamil');
      expect(tamil.length, 7);

      final english = CanonicalSyllabus.getChapters('english');
      expect(english.length, 7);

      final maths = CanonicalSyllabus.getChapters('mathematics');
      expect(maths.length, 8);

      final science = CanonicalSyllabus.getChapters('science');
      expect(science.length, 23);

      final social = CanonicalSyllabus.getChapters('social_science');
      expect(social.length, 11);

      final allChapters = CanonicalSyllabus.getAllChapters();
      expect(allChapters.length, 56);
    });

    test('retrieves specific chapter details accurately', () {
      final science = CanonicalSyllabus.getChapters('science');
      final electricity = science.firstWhere((c) => c.title.toLowerCase().contains('electricity'));
      expect(electricity.chapterNumber, 4);
      expect(electricity.title, 'Electricity');
    });
  });

  group('ChapterMastery and MasteryLevel', () {
    test('notStarted when 0 attempts', () {
      const ch = ChapterMastery(
        subjectId: 'mathematics',
        chapterId: 'mat_ch03',
        chapterTitle: 'Algebra',
        chapterNumber: 3,
        totalAttempts: 0,
        correctAttempts: 0,
        activeMistakes: 0,
      );
      expect(ch.masteryLevel, MasteryLevel.notStarted);
      expect(ch.accuracy, 0.0);
      expect(ch.isMastered, isFalse);
    });

    test('needsPractice when accuracy is below 70% or active mistakes exist', () {
      const lowAccuracy = ChapterMastery(
        subjectId: 'mathematics',
        chapterId: 'mat_ch03',
        chapterTitle: 'Algebra',
        chapterNumber: 3,
        totalAttempts: 10,
        correctAttempts: 5, // 50%
        activeMistakes: 1,
      );
      expect(lowAccuracy.masteryLevel, MasteryLevel.needsPractice);
      expect(lowAccuracy.accuracy, 0.5);

      const withMistakes = ChapterMastery(
        subjectId: 'mathematics',
        chapterId: 'mat_ch03',
        chapterTitle: 'Algebra',
        chapterNumber: 3,
        totalAttempts: 10,
        correctAttempts: 8, // 80%
        activeMistakes: 1, // active mistake prevents proficient/mastered
      );
      expect(withMistakes.masteryLevel, MasteryLevel.needsPractice);
    });

    test('proficient when >=70% accuracy with at least 3 attempts and 0 active mistakes', () {
      const ch = ChapterMastery(
        subjectId: 'science',
        chapterId: 'sci_ch02',
        chapterTitle: 'Optics',
        chapterNumber: 2,
        totalAttempts: 4,
        correctAttempts: 3, // 75%
        activeMistakes: 0,
      );
      expect(ch.masteryLevel, MasteryLevel.proficient);
      expect(ch.isMastered, isFalse);
    });

    test('mastered when >=85% accuracy with at least 5 attempts and 0 active mistakes', () {
      const ch = ChapterMastery(
        subjectId: 'science',
        chapterId: 'sci_ch02',
        chapterTitle: 'Optics',
        chapterNumber: 2,
        totalAttempts: 10,
        correctAttempts: 9, // 90%
        activeMistakes: 0,
      );
      expect(ch.masteryLevel, MasteryLevel.mastered);
      expect(ch.isMastered, isTrue);
    });
  });

  group('SubjectMastery aggregations', () {
    test('computes correct aggregates and strongest/weakest chapters', () {
      const ch1 = ChapterMastery(
        subjectId: 'science',
        chapterId: 'sci_ch01',
        chapterTitle: 'Laws of Motion',
        chapterNumber: 1,
        totalAttempts: 10,
        correctAttempts: 9, // 90%, 0 mistakes -> Mastered
        activeMistakes: 0,
      );
      const ch2 = ChapterMastery(
        subjectId: 'science',
        chapterId: 'sci_ch02',
        chapterTitle: 'Optics',
        chapterNumber: 2,
        totalAttempts: 10,
        correctAttempts: 5, // 50%, 3 mistakes -> Needs Practice
        activeMistakes: 3,
      );
      const ch3 = ChapterMastery(
        subjectId: 'science',
        chapterId: 'sci_ch03',
        chapterTitle: 'Thermal Physics',
        chapterNumber: 3,
        totalAttempts: 0,
        correctAttempts: 0,
        activeMistakes: 0,
      );

      const subjectMastery = SubjectMastery(
        subjectId: 'science',
        displayName: 'Science',
        chapters: [ch1, ch2, ch3],
      );

      expect(subjectMastery.totalChapters, 3);
      expect(subjectMastery.attemptedChapters, 2);
      expect(subjectMastery.masteredChapters, 1);
      expect(subjectMastery.needsPracticeChapters, 1);
      expect(subjectMastery.notStartedChapters, 1);
      expect(subjectMastery.totalAttempts, 20);
      expect(subjectMastery.totalCorrect, 14);
      expect(subjectMastery.overallAccuracy, 0.7); // 14 / 20 = 70%
      expect(subjectMastery.activeMistakes, 3);
      expect(subjectMastery.coveragePercent, closeTo(0.666, 0.01));

      // Strongest chapter should be ch1 (90%)
      expect(subjectMastery.strongestChapter?.chapterTitle, 'Laws of Motion');
      // Weakest focus chapter should be ch2 (50% with 3 active mistakes)
      expect(subjectMastery.weakestChapter?.chapterTitle, 'Optics');
    });
  });
}
