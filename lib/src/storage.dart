// Copyright (c) 2025, ThreadBox MCP contributors.

/// Storage layer for ThreadBox using SQLite with UUID-based addressing.
library;

import 'dart:async';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

/// Manages file storage with append-only immutability and version history.
class FileStorage {
  final SqliteDatabase _db;
  final Uuid _uuid = const Uuid();
  bool _initialized = false;

  FileStorage(String dbPath) : _db = SqliteDatabase(path: dbPath);

  /// Initialize the database schema.
  Future<void> _initDatabase() async {
    if (_initialized) return;

    // Create tables for file storage with UUID primary keys
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        content BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        session_id TEXT,
        version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_session_id ON files(session_id)
    ''');

    _initialized = true;
  }

  /// Ensures database is initialized before operations.
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _initDatabase();
    }
  }

  /// Writes a file to storage and returns its UUID (inode ID).
  Future<String> writeFile(String path, List<int> content, {String? sessionId}) async {
    await _ensureInitialized();
    
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Get version number for this path (considering session isolation)
    final whereClause = sessionId != null
        ? 'path = ? AND session_id = ?'
        : 'path = ?';
    final params = sessionId != null ? [path, sessionId] : [path];
    
    final versionResult = await _db.get('''
      SELECT MAX(version) as max_version 
      FROM files 
      WHERE $whereClause
    ''', params);
    
    final version = versionResult != null && versionResult['max_version'] != null
        ? (versionResult['max_version'] as int) + 1
        : 1;

    await _db.execute(
      'INSERT INTO files (id, path, content, created_at, session_id, version) VALUES (?, ?, ?, ?, ?, ?)',
      [id, path, content, timestamp, sessionId, version],
    );

    return id;
  }

  /// Reads the latest version of a file by path.
  Future<FileRecord?> readFile(String path, {String? sessionId}) async {
    await _ensureInitialized();
    
    final whereClause = sessionId != null
        ? 'path = ? AND session_id = ?'
        : 'path = ?';
    final params = sessionId != null ? [path, sessionId] : [path];

    final row = await _db.get('''
      SELECT id, path, content, created_at, session_id, version 
      FROM files 
      WHERE $whereClause 
      ORDER BY version DESC 
      LIMIT 1
    ''', params);

    if (row == null) return null;

    return FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sessionId: row['session_id'] as String?,
      version: row['version'] as int,
    );
  }

  /// Lists all files in a directory.
  Future<List<FileRecord>> listDirectory(String dirPath, {String? sessionId}) async {
    await _ensureInitialized();
    
    // Normalize directory path
    final normalizedPath = dirPath.endsWith('/') ? dirPath : '$dirPath/';

    final whereClause = sessionId != null
        ? 'path LIKE ? AND session_id = ?'
        : 'path LIKE ?';
    final params = sessionId != null
        ? ['$normalizedPath%', sessionId]
        : ['$normalizedPath%'];

    // Get latest versions only
    final rows = await _db.getAll('''
      SELECT id, path, content, created_at, session_id, version
      FROM files
      WHERE $whereClause
        AND version = (
          SELECT MAX(version)
          FROM files f2
          WHERE f2.path = files.path
            ${sessionId != null ? 'AND f2.session_id = files.session_id' : ''}
        )
      ORDER BY path
    ''', params);

    return rows.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sessionId: row['session_id'] as String?,
      version: row['version'] as int,
    )).toList();
  }

  /// Gets all versions of a file.
  Future<List<FileRecord>> getFileHistory(String path, {String? sessionId}) async {
    await _ensureInitialized();
    
    final whereClause = sessionId != null
        ? 'path = ? AND session_id = ?'
        : 'path = ?';
    final params = sessionId != null ? [path, sessionId] : [path];

    final rows = await _db.getAll('''
      SELECT id, path, content, created_at, session_id, version 
      FROM files 
      WHERE $whereClause 
      ORDER BY version DESC
    ''', params);

    return rows.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sessionId: row['session_id'] as String?,
      version: row['version'] as int,
    )).toList();
  }

  /// Gets all files in a session.
  Future<List<FileRecord>> getSessionFiles(String sessionId) async {
    await _ensureInitialized();
    
    final rows = await _db.getAll('''
      SELECT id, path, content, created_at, session_id, version
      FROM files
      WHERE session_id = ?
        AND version = (
          SELECT MAX(version)
          FROM files f2
          WHERE f2.path = files.path
            AND f2.session_id = files.session_id
        )
      ORDER BY path
    ''', [sessionId]);

    return rows.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      sessionId: row['session_id'] as String?,
      version: row['version'] as int,
    )).toList();
  }

  /// Gets all session IDs.
  Future<List<String>> getAllSessions() async {
    await _ensureInitialized();
    
    final rows = await _db.getAll('''
      SELECT DISTINCT session_id
      FROM files
      WHERE session_id IS NOT NULL
      ORDER BY session_id
    ''');

    return rows.map((row) => row['session_id'] as String).toList();
  }

  /// Moves a file from one path to another.
  /// Creates a new version at the new path with the same content.
  Future<String> moveFile(String fromPath, String toPath, {String? sessionId}) async {
    await _ensureInitialized();
    
    // Read the latest version of the source file
    final sourceFile = await readFile(fromPath, sessionId: sessionId);
    if (sourceFile == null) {
      throw Exception('Source file not found: $fromPath');
    }

    // Write to the new path (this creates a new version)
    return await writeFile(toPath, sourceFile.content, sessionId: sessionId);
  }

  /// Renames a file (alias for moveFile).
  Future<String> renameFile(String oldPath, String newPath, {String? sessionId}) async {
    return await moveFile(oldPath, newPath, sessionId: sessionId);
  }

  /// Closes the database connection.
  Future<void> close() async {
    await _db.close();
  }
}

/// Represents a file record in storage.
class FileRecord {
  final String id;
  final String path;
  final List<int> content;
  final DateTime createdAt;
  final String? sessionId;
  final int version;

  FileRecord({
    required this.id,
    required this.path,
    required this.content,
    required this.createdAt,
    this.sessionId,
    required this.version,
  });
}
