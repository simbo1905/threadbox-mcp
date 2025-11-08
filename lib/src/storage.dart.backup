// Copyright (c) 2025, ThreadBox MCP contributors.

/// Storage layer for ThreadBox using SQLite with UUID-based addressing.
library;

import 'dart:async';
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// Manages file storage with append-only immutability and version history.
class FileStorage {
  final SqliteDatabase _db;
  final Uuid _uuid = const Uuid();

  FileStorage._(this._db);

  /// Creates a new FileStorage instance with the given database path.
  static Future<FileStorage> create(String dbPath) async {
    final db = SqliteDatabase(path: dbPath);
    final storage = FileStorage._(db);
    await storage._initDatabase();
    return storage;
  }

  Future<void> _initDatabase() async {
    // Create tables for file storage with UUID primary keys
    await _db.execute('''
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY,
        path TEXT NOT NULL,
        content BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        worktree TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        parent_path TEXT,
        is_directory INTEGER NOT NULL DEFAULT 0,
        metadata TEXT
      )
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_path ON files(path)
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_worktree ON files(worktree)
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_parent ON files(parent_path)
    ''');

    await _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_files_deleted ON files(is_deleted)
    ''');
  }

  /// Writes a file to storage and returns its UUID.
  Future<String> writeFile(String path, List<int> content, {String? worktree, String? metadata}) async {
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final parentPath = _getParentPath(path);

    // Get version number for this path
    final result = await _db.getAll(
      'SELECT MAX(version) as max_version FROM files WHERE path = ? AND is_deleted = 0',
      [path],
    );
    final version = result.isNotEmpty && result.first['max_version'] != null
        ? (result.first['max_version'] as int) + 1
        : 1;

    await _db.execute(
      'INSERT INTO files (id, path, content, created_at, worktree, version, is_deleted, parent_path, is_directory, metadata) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, ?, 0, ?)',
      [id, path, content, timestamp, worktree, version, parentPath, metadata],
    );

    return id;
  }

  /// Creates a directory entry in the virtual filesystem.
  Future<String> createDirectory(String path, {String? worktree, String? metadata}) async {
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final parentPath = _getParentPath(path);
    final normalizedPath = _normalizeDirPath(path);

    // Check if directory already exists
    final existing = await readFile(normalizedPath, worktree: worktree);
    if (existing != null && existing.isDirectory) {
      return existing.id;
    }

    // Get version number
    final result = await _db.getAll(
      'SELECT MAX(version) as max_version FROM files WHERE path = ? AND is_deleted = 0',
      [normalizedPath],
    );
    final version = result.isNotEmpty && result.first['max_version'] != null
        ? (result.first['max_version'] as int) + 1
        : 1;

    await _db.execute(
      'INSERT INTO files (id, path, content, created_at, worktree, version, is_deleted, parent_path, is_directory, metadata) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, ?, 1, ?)',
      [id, normalizedPath, <int>[], timestamp, worktree, version, parentPath, metadata],
    );

    return id;
  }

  /// Reads the latest version of a file by path.
  Future<FileRecord?> readFile(String path, {String? worktree}) async {
    final whereClause = worktree != null
        ? 'path = ? AND worktree = ?'
        : 'path = ?';
    final params = worktree != null ? [path, worktree] : [path];

    final result = await _db.getAll(
      'SELECT id, path, content, created_at, worktree, version, is_directory, is_deleted, metadata FROM files '
      'WHERE $whereClause ORDER BY version DESC LIMIT 1',
      params,
    );

    if (result.isEmpty) return null;

    final row = result.first;
    // If the latest version is deleted, return null
    if ((row['is_deleted'] as int) == 1) return null;

    return FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
      isDirectory: (row['is_directory'] as int) == 1,
      metadata: row['metadata'] as String?,
    );
  }

  /// Lists all files in a directory (non-recursive).
  Future<List<FileRecord>> listDirectory(String dirPath, {String? worktree, bool recursive = false}) async {
    // Normalize directory path
    final normalizedPath = _normalizeDirPath(dirPath);

    final whereClause = worktree != null
        ? 'path LIKE ? AND worktree = ?'
        : 'path LIKE ?';
    
    final pattern = recursive ? '$normalizedPath%' : '$normalizedPath%';
    final params = worktree != null ? [pattern, worktree] : [pattern];

    // Get latest versions only, excluding the directory itself
    final result = await _db.getAll('''
      WITH LatestVersions AS (
        SELECT path, MAX(version) as max_version, worktree
        FROM files
        WHERE $whereClause
          AND path != ?
        GROUP BY path, worktree
      )
      SELECT f.id, f.path, f.content, f.created_at, f.worktree, f.version, f.is_directory, f.metadata
      FROM files f
      INNER JOIN LatestVersions lv
        ON f.path = lv.path 
        AND f.version = lv.max_version
        AND (f.worktree = lv.worktree OR (f.worktree IS NULL AND lv.worktree IS NULL))
      WHERE f.is_deleted = 0
      ORDER BY f.path
    ''', [...params, normalizedPath]);

    final records = result.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
      isDirectory: (row['is_directory'] as int) == 1,
      metadata: row['metadata'] as String?,
    )).toList();

    // Filter for non-recursive: only immediate children
    if (!recursive) {
      return records.where((r) {
        if (r.path.length <= normalizedPath.length) return false;
        final relativePath = r.path.substring(normalizedPath.length);
        // Immediate children should have:
        // - No slashes (for files): "file.txt"
        // - Exactly one slash at the end (for directories): "subdir/"
        if (relativePath.contains('/')) {
          // If it has slashes, it should end with exactly one slash (directory)
          return relativePath.endsWith('/') && relativePath.indexOf('/') == relativePath.length - 1;
        }
        return true; // No slashes = immediate file
      }).toList();
    }

    return records;
  }

  /// Moves a file or directory to a new path.
  Future<String> moveFile(String sourcePath, String destPath, {String? worktree}) async {
    // Try reading as file first, then as directory
    var source = await readFile(sourcePath, worktree: worktree);
    if (source == null) {
      // Try with trailing slash (directory)
      source = await readFile(_normalizeDirPath(sourcePath), worktree: worktree);
      if (source == null) {
        throw Exception('Source file not found: $sourcePath');
      }
    }

    // If moving a directory, move all children
    if (source.isDirectory) {
      final normalizedSource = _normalizeDirPath(sourcePath);
      final normalizedDest = _normalizeDirPath(destPath);
      
      final children = await listDirectory(normalizedSource, worktree: worktree, recursive: true);
      
      // Move directory itself
      final dirId = await writeFile(
        normalizedDest,
        <int>[],
        worktree: worktree,
        metadata: source.metadata,
      );
      
      // Update the directory flag
      await _db.execute(
        'UPDATE files SET is_directory = 1 WHERE id = ?',
        [dirId],
      );

      // Move all children
      for (final child in children) {
        if (child.path == normalizedSource) continue;
        final relativePath = child.path.substring(normalizedSource.length);
        final newPath = '$normalizedDest$relativePath';
        await writeFile(newPath, child.content, worktree: worktree, metadata: child.metadata);
      }

      // Mark source as deleted
      await _markDeleted(normalizedSource, worktree: worktree);
      for (final child in children) {
        await _markDeleted(child.path, worktree: worktree);
      }

      return dirId;
    } else {
      // Move regular file
      final newId = await writeFile(destPath, source.content, worktree: worktree, metadata: source.metadata);
      await _markDeleted(sourcePath, worktree: worktree);
      return newId;
    }
  }

  /// Renames a file or directory.
  Future<String> renameFile(String path, String newName, {String? worktree}) async {
    // Extract parent directory preserving leading slash
    final lastSlash = path.lastIndexOf('/');
    final newPath = lastSlash >= 0 ? '${path.substring(0, lastSlash + 1)}$newName' : newName;
    return moveFile(path, newPath, worktree: worktree);
  }

  /// Copies a file or directory.
  Future<String> copyFile(String sourcePath, String destPath, {String? worktree}) async {
    // Try reading as file first, then as directory
    var source = await readFile(sourcePath, worktree: worktree);
    if (source == null) {
      // Try with trailing slash (directory)
      source = await readFile(_normalizeDirPath(sourcePath), worktree: worktree);
      if (source == null) {
        throw Exception('Source file not found: $sourcePath');
      }
    }

    if (source.isDirectory) {
      final normalizedSource = _normalizeDirPath(sourcePath);
      final normalizedDest = _normalizeDirPath(destPath);
      
      final children = await listDirectory(normalizedSource, worktree: worktree, recursive: true);
      
      // Copy directory itself
      final dirId = await createDirectory(normalizedDest, worktree: worktree, metadata: source.metadata);

      // Copy all children
      for (final child in children) {
        if (child.path == normalizedSource) continue;
        final relativePath = child.path.substring(normalizedSource.length);
        final newPath = '$normalizedDest$relativePath';
        await writeFile(newPath, child.content, worktree: worktree, metadata: child.metadata);
      }

      return dirId;
    } else {
      return writeFile(destPath, source.content, worktree: worktree, metadata: source.metadata);
    }
  }

  /// Deletes a file or directory (marks as deleted).
  Future<void> deleteFile(String path, {String? worktree, bool recursive = false}) async {
    // Try reading as file first, then as directory
    var file = await readFile(path, worktree: worktree);
    if (file == null) {
      // Try with trailing slash (directory)
      file = await readFile(_normalizeDirPath(path), worktree: worktree);
      if (file == null) {
        throw Exception('File not found: $path');
      }
    }

    if (file.isDirectory) {
      final normalizedPath = _normalizeDirPath(path);
      if (!recursive) {
        // Check if directory is empty
        final children = await listDirectory(normalizedPath, worktree: worktree);
        if (children.isNotEmpty) {
          throw Exception('Directory not empty: $path. Use recursive=true to delete non-empty directories.');
        }
      } else {
        // Delete all children recursively
        final children = await listDirectory(normalizedPath, worktree: worktree, recursive: true);
        
        for (final child in children) {
          await _markDeleted(child.path, worktree: worktree);
        }
      }

      // Delete the directory itself
      await _markDeleted(normalizedPath, worktree: worktree);
    } else {
      await _markDeleted(path, worktree: worktree);
    }
  }

  /// Gets metadata for a file or directory.
  Future<FileMetadata?> getMetadata(String path, {String? worktree}) async {
    // Try reading as file first, then as directory
    var file = await readFile(path, worktree: worktree);
    if (file == null) {
      // Try with trailing slash (directory)
      file = await readFile(_normalizeDirPath(path), worktree: worktree);
      if (file == null) return null;
    }

    int? size;
    int? childCount;

    if (file.isDirectory) {
      final children = await listDirectory(path, worktree: worktree);
      childCount = children.where((c) => c.path != _normalizeDirPath(path)).length;
      size = 0;
    } else {
      size = file.content.length;
    }

    return FileMetadata(
      path: file.path,
      isDirectory: file.isDirectory,
      size: size,
      createdAt: file.createdAt,
      version: file.version,
      worktree: file.worktree,
      childCount: childCount,
      customMetadata: file.metadata,
    );
  }

  /// Gets all versions of a file.
  Future<List<FileRecord>> getFileHistory(String path, {String? worktree}) async {
    final whereClause = worktree != null
        ? 'path = ? AND worktree = ?'
        : 'path = ?';
    final params = worktree != null ? [path, worktree] : [path];

    final result = await _db.getAll(
      'SELECT id, path, content, created_at, worktree, version, is_directory, metadata FROM files '
      'WHERE $whereClause ORDER BY version DESC',
      params,
    );

    return result.map((row) => FileRecord(
      id: row['id'] as String,
      path: row['path'] as String,
      content: row['content'] as List<int>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      worktree: row['worktree'] as String?,
      version: row['version'] as int,
      isDirectory: (row['is_directory'] as int) == 1,
      metadata: row['metadata'] as String?,
    )).toList();
  }

  /// Checks if a path exists.
  Future<bool> exists(String path, {String? worktree}) async {
    final file = await readFile(path, worktree: worktree);
    return file != null;
  }

  /// Lists all worktrees in the database.
  Future<List<String>> listWorktrees() async {
    // Get worktrees that have at least one non-deleted file in latest version
    final result = await _db.getAll('''
      SELECT DISTINCT worktree
      FROM files f1
      WHERE worktree IS NOT NULL
        AND is_deleted = 0
        AND version = (
          SELECT MAX(version)
          FROM files f2
          WHERE f2.path = f1.path
            AND f2.worktree = f1.worktree
        )
      ORDER BY worktree
    ''');
    return result.map((row) => row['worktree'] as String).toList();
  }

  /// Marks a file as deleted by creating a new version with is_deleted flag.
  Future<void> _markDeleted(String path, {String? worktree}) async {
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final parentPath = _getParentPath(path);

    // Get version number
    final result = await _db.getAll(
      'SELECT MAX(version) as max_version FROM files WHERE path = ?',
      [path],
    );
    final version = result.isNotEmpty && result.first['max_version'] != null
        ? (result.first['max_version'] as int) + 1
        : 1;

    await _db.execute(
      'INSERT INTO files (id, path, content, created_at, worktree, version, is_deleted, parent_path, is_directory) '
      'VALUES (?, ?, ?, ?, ?, ?, 1, ?, 0)',
      [id, path, <int>[], timestamp, worktree, version, parentPath],
    );
  }

  /// Gets the parent path of a file path.
  String _getParentPath(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    final dirname = p.dirname(normalized);
    return dirname == '.' ? '' : dirname;
  }

  /// Normalizes a directory path to end with '/'.
  String _normalizeDirPath(String path) {
    return path.endsWith('/') ? path : '$path/';
  }

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
  final String? worktree;
  final int version;
  final bool isDirectory;
  final String? metadata;

  FileRecord({
    required this.id,
    required this.path,
    required this.content,
    required this.createdAt,
    this.worktree,
    required this.version,
    this.isDirectory = false,
    this.metadata,
  });
}

/// Represents file metadata.
class FileMetadata {
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime createdAt;
  final int version;
  final String? worktree;
  final int? childCount;
  final String? customMetadata;

  FileMetadata({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.createdAt,
    required this.version,
    this.worktree,
    this.childCount,
    this.customMetadata,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'isDirectory': isDirectory,
    'size': size,
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'worktree': worktree,
    'childCount': childCount,
    'customMetadata': customMetadata,
  };
}
