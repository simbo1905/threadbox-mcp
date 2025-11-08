// Copyright (c) 2025, ThreadBox MCP contributors.

/// Storage layer for ThreadBox using SQLite with UUID-based addressing.
library;

import 'dart:async';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

/// Manages file storage with append-only immutability and version history.
class FileStorage {
  final Database _db;
  final Uuid _uuid = const Uuid();

  FileStorage(String dbPath) : _db = sqlite3.open(dbPath) {
    _initDatabase();
  }

  void _initDatabase() {
    // Create tables for file storage with UUID primary keys
    _db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        content BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        worktree TEXT,
        version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_worktree ON files(worktree)
    ''');
  }

  /// Writes a file to storage and returns its UUID.
  Future<String> writeFile(String path, List<int> content, {String? worktree}) async {
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Get version number for this path
    final stmt = _db.prepare('SELECT MAX(version) as max_version FROM files WHERE path = ?');
    final result = stmt.select([path]);
    final version = result.isNotEmpty && result.first['max_version'] != null
        ? (result.first['max_version'] as int) + 1
        : 1;
    stmt.dispose();

    _db.execute(
      'INSERT INTO files (id, path, content, created_at, worktree, version) VALUES (?, ?, ?, ?, ?, ?)',
      [id, path, content, timestamp, worktree, version],
    );

    return id;
  }

  /// Reads the latest version of a file by path.
  Future<FileRecord?> readFile(String path, {String? worktree}) async {
    final whereClause = worktree != null
        ? 'path = ? AND worktree = ?'
        : 'path = ?';
    final params = worktree != null ? [path, worktree] : [path];

    final stmt = _db.prepare(
      'SELECT id, path, content, created_at, worktree, version FROM files '
      'WHERE $whereClause ORDER BY version DESC LIMIT 1',
    );

    final result = stmt.select(params);
    stmt.dispose();

    if (result.isEmpty) return null;

    final row = result.first;
    return FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
    );
  }

  /// Lists all files in a directory.
  Future<List<FileRecord>> listDirectory(String dirPath, {String? worktree}) async {
    // Normalize directory path
    final normalizedPath = dirPath.endsWith('/') ? dirPath : '$dirPath/';

    final whereClause = worktree != null
        ? 'path LIKE ? AND worktree = ?'
        : 'path LIKE ?';
    final params = worktree != null
        ? ['$normalizedPath%', worktree]
        : ['$normalizedPath%'];

    // Get latest versions only
    final stmt = _db.prepare('''
      SELECT id, path, content, created_at, worktree, version
      FROM files
      WHERE $whereClause
        AND version = (
          SELECT MAX(version)
          FROM files f2
          WHERE f2.path = files.path
            ${worktree != null ? 'AND f2.worktree = files.worktree' : ''}
        )
      ORDER BY path
    ''');

    final result = stmt.select(params);
    stmt.dispose();

    return result.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
    )).toList();
  }

  /// Gets all versions of a file.
  Future<List<FileRecord>> getFileHistory(String path, {String? worktree}) async {
    final whereClause = worktree != null
        ? 'path = ? AND worktree = ?'
        : 'path = ?';
    final params = worktree != null ? [path, worktree] : [path];

    final stmt = _db.prepare(
      'SELECT id, path, content, created_at, worktree, version FROM files '
      'WHERE $whereClause ORDER BY version DESC',
    );

    final result = stmt.select(params);
    stmt.dispose();

    return result.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
    )).toList();
  }

  void close() {
    _db.dispose();
  }
}

/// Represents a file record in storage.
class FileRecord {
  final String id;
  final String path;
  final List<int> content;
  final DateTime createdAt;
  final String? worktree;
  final int version;

  FileRecord({
    required this.id,
    required this.path,
    required this.content,
    required this.createdAt,
    this.worktree,
    required this.version,
  });
}
