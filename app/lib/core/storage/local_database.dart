import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class LocalDatabase {
  static const _dbName = 'boardmate10.db';
  static const _dbVersion = 3;
  Database? _db;
  bool _schemaVerified = false;

  Future<Database> get db async {
    _db ??= await _open();
    if (!_schemaVerified) {
      await _ensureColumnsAndTablesExist(_db!);
      _schemaVerified = true;
    }
    return _db!;
  }

  Future<Database> _open() async {
    Database database;
    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWebNoWebWorker;
      database = await databaseFactory.openDatabase(
        _dbName,
        options: OpenDatabaseOptions(
          version: _dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    } else {
      final dbsPath = await getDatabasesPath();
      final path = join(dbsPath, _dbName);
      database = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    await _ensureColumnsAndTablesExist(database);
    return database;
  }

  Future<void> _ensureColumnsAndTablesExist(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_questions (
        question_id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL,
        data_json TEXT NOT NULL,
        cached_at TEXT NOT NULL,
        content_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_attempts (
        attempt_id TEXT PRIMARY KEY,
        local_student_id TEXT NOT NULL,
        question_id TEXT NOT NULL,
        subject_id TEXT,
        chapter_id TEXT,
        selected_option_id TEXT,
        is_correct INTEGER NOT NULL DEFAULT 0,
        mode TEXT NOT NULL DEFAULT 'practice',
        attempted_at TEXT NOT NULL,
        question_content_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // Safe column migrations: Check PRAGMA table_info
    try {
      final info = await db.rawQuery("PRAGMA table_info(student_attempts)");
      final cols = info
          .map((r) => (r['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet();

      if (!cols.contains('subject_id')) {
        await db.execute('ALTER TABLE student_attempts ADD COLUMN subject_id TEXT');
      }
      if (!cols.contains('chapter_id')) {
        await db.execute('ALTER TABLE student_attempts ADD COLUMN chapter_id TEXT');
      }
    } catch (e) {
      debugPrint('LocalDatabase column migration note: $e');
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_questions (
        question_id TEXT NOT NULL,
        local_student_id TEXT NOT NULL,
        saved_at TEXT NOT NULL,
        notes TEXT,
        PRIMARY KEY (question_id, local_student_id)
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attempts_student
        ON student_attempts(local_student_id, question_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_attempts_subject_chapter
        ON student_attempts(local_student_id, subject_id, chapter_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cached_subject_chapter
        ON cached_questions(subject_id, chapter_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_saved_student
        ON saved_questions(local_student_id)
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await _ensureColumnsAndTablesExist(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _ensureColumnsAndTablesExist(db);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
    _schemaVerified = false;
  }
}
