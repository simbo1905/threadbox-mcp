// Copyright (c) 2025, ThreadBox MCP contributors.

/// Storage layer for ThreadBox using sqlite_async with UUID-based addressing.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart' as sqlite;
import 'package:sqlite_async/sqlite_async.dart';
import 'package:uuid/uuid.dart';

/// Enumeration for the supported node types in the virtual filesystem.
enum NodeType { file, directory }

/// Lightweight exception type for storage level failures.
class StorageException implements Exception {
  StorageException(this.message);

  final String message;

  @override
  String toString() => 'StorageException: $message';
}

/// Represents an entry (file or directory) stored in the virtual filesystem.
class VirtualEntry {
  const VirtualEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    required this.worktree,
    this.parentPath,
    this.content,
  });

  final String id;
  final String path;
  final String name;
  final NodeType type;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String worktree;
  final String? parentPath;
  final Uint8List? content;

  Map<String, Object?> toJson({bool includeContent = false}) {
    return {
      'id': id,
      'path': path,
      'name': name,
      'parentPath': parentPath,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'worktree': worktree.isEmpty ? null : worktree,
      if (includeContent && content != null)
        'content': base64Encode(content!),
    };
  }
}

/// Manages virtual filesystem state backed by sqlite_async.
class FileStorage {
  FileStorage._(this._db, this._uuid);

  final SqliteDatabase _db;
  final Uuid _uuid;

  /// Opens the storage at [dbPath], creating tables as needed.
  static Future<FileStorage> open(String dbPath) async {
    final database = SqliteDatabase(path: dbPath);
    final storage = FileStorage._(database, const Uuid());
    await storage._initDatabase();
    return storage;
  }

  Future<void> _initDatabase() async {
    await _db.writeTransaction((tx) async {
      await tx.execute('''
        CREATE TABLE IF NOT EXISTS nodes (
          id TEXT PRIMARY KEY,
          path TEXT NOT NULL,
          name TEXT NOT NULL,
          parent_path TEXT,
          type TEXT NOT NULL CHECK (type IN ('file', 'directory')),
          content BLOB,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          worktree TEXT NOT NULL DEFAULT ''
        )
      ''');

      await tx.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_nodes_worktree_path
        ON nodes(worktree, path)
      ''');

      await tx.execute('''
        CREATE INDEX IF NOT EXISTS idx_nodes_parent
        ON nodes(worktree, parent_path)
      ''');

      await _ensureWorktreeRoot(tx, '');
    });
  }

  /// Creates a file at [path] with [content].
  Future<VirtualEntry> createFile(
    String path,
    List<int> content, {
    String? worktree,
  }) async {
    final normalizedWorktree = _normalizeWorktree(worktree);
    final normalizedPath = _normalizePath(path);
    final parent = _parentPath(normalizedPath);
    final now = _timestamp();
    final name = _basename(normalizedPath);

    return _db.writeTransaction((tx) async {
      await _ensureWorktreeRoot(tx, normalizedWorktree);
      if (parent != null) {
        await _ensureDirectory(tx, parent, normalizedWorktree);
      }

      final existing = await tx.getOptional(
        'SELECT id FROM nodes WHERE worktree = ? AND path = ?',
        [normalizedWorktree, normalizedPath],
      );
      if (existing != null) {
        throw StorageException('A node already exists at $normalizedPath');
      }

      final id = _uuid.v4();
      final bytes = Uint8List.fromList(List<int>.from(content));
      await tx.execute(
        '''
        INSERT INTO nodes (
          id, path, name, parent_path, type, content,
          created_at, updated_at, worktree
        )
        VALUES (?, ?, ?, ?, 'file', ?, ?, ?, ?)
        ''',
        [
          id,
          normalizedPath,
          name,
          parent,
          bytes,
          now,
          now,
          normalizedWorktree,
        ],
      );

      return VirtualEntry(
        id: id,
        path: normalizedPath,
        name: name,
        parentPath: parent,
        type: NodeType.file,
        content: bytes,
        createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        worktree: normalizedWorktree,
      );
    });
  }

  /// Reads a file entry located at [path].
  Future<VirtualEntry?> readFile(String path, {String? worktree}) async {
    final normalizedWorktree = _normalizeWorktree(worktree);
    final normalizedPath = _normalizePath(path);

    final row = await _db.getOptional(
      '''
      SELECT *
      FROM nodes
      WHERE worktree = ? AND path = ? AND type = 'file'
      ''',
      [normalizedWorktree, normalizedPath],
    );

    if (row == null) return null;
    return _rowToEntry(row);
  }

  /// Lists all direct children of the directory at [dirPath].
  Future<List<VirtualEntry>> listDirectory(
    String dirPath, {
    String? worktree,
  }) async {
    final normalizedWorktree = _normalizeWorktree(worktree);
    final normalizedPath = _normalizePath(dirPath);

    await _assertDirectoryExists(normalizedPath, normalizedWorktree);

    final rows = await _db.getAll(
      '''
      SELECT *
      FROM nodes
      WHERE worktree = ? AND parent_path = ?
      ORDER BY type DESC, name ASC
      ''',
      [normalizedWorktree, normalizedPath],
    );

    return rows.map(_rowToEntry).toList();
  }

  /// Renames the node at [path] to [newName] within the same directory.
  Future<VirtualEntry> renameNode(
    String path,
    String newName, {
    String? worktree,
  }) async {
    final normalizedName = _normalizeName(newName);
    final normalizedWorktree = _normalizeWorktree(worktree);
    final normalizedPath = _normalizePath(path);
    final parent = _parentPath(normalizedPath);
    if (parent == null) {
      throw StorageException('Cannot rename the root directory');
    }

    final targetPath = _joinPath(parent, normalizedName);
    return _updatePath(normalizedPath, targetPath, normalizedWorktree);
  }

  /// Moves the node at [path] to a new parent directory located at [newDirectoryPath].
  Future<VirtualEntry> moveNode(
    String path,
    String newDirectoryPath, {
    String? worktree,
  }) async {
    final normalizedWorktree = _normalizeWorktree(worktree);
    final normalizedPath = _normalizePath(path);
    final name = _basename(normalizedPath);
    final targetDirectory = _normalizePath(newDirectoryPath);
    if (targetDirectory == normalizedPath) {
      throw StorageException('Destination directory matches the file path');
    }
    final targetPath = _joinPath(targetDirectory, name);
    return _updatePath(normalizedPath, targetPath, normalizedWorktree);
  }

  /// Closes the underlying sqlite database connections.
  Future<void> close() => _db.close();

  Future<VirtualEntry> _updatePath(
    String fromPath,
    String toPath,
    String worktree,
  ) async {
    if (fromPath == '/') {
      throw StorageException('Cannot move the root directory');
    }

    final normalizedTarget = _normalizePath(toPath);
    final newParent = _parentPath(normalizedTarget);
    if (newParent == null) {
      throw StorageException('Files must reside inside a directory');
    }

    return _db.writeTransaction((tx) async {
      await _ensureWorktreeRoot(tx, worktree);

      final source = await tx.getOptional(
        'SELECT * FROM nodes WHERE worktree = ? AND path = ?',
        [worktree, fromPath],
      );
      if (source == null) {
        throw StorageException('No node found at $fromPath');
      }

      final type = source['type'] as String;
      if (type != 'file') {
        throw StorageException('Only file nodes can be moved in this release');
      }

      final conflict = await tx.getOptional(
        'SELECT id FROM nodes WHERE worktree = ? AND path = ?',
        [worktree, normalizedTarget],
      );
      if (conflict != null) {
        throw StorageException('A node already exists at $normalizedTarget');
      }

      await _ensureDirectory(tx, newParent, worktree);

      final now = _timestamp();
      await tx.execute(
        '''
        UPDATE nodes
        SET path = ?, name = ?, parent_path = ?, updated_at = ?
        WHERE id = ?
        ''',
        [
          normalizedTarget,
          _basename(normalizedTarget),
          newParent,
          now,
          source['id'] as String,
        ],
      );

      final updated = await tx.get(
        'SELECT * FROM nodes WHERE id = ?',
        [source['id'] as String],
      );

      return _rowToEntry(updated);
    });
  }

  Future<void> _ensureWorktreeRoot(
    SqliteWriteContext tx,
    String worktree,
  ) async {
    final existing = await tx.getOptional(
      'SELECT id FROM nodes WHERE worktree = ? AND path = ?',
      [worktree, '/'],
    );
    if (existing != null) return;

    final now = _timestamp();
    await tx.execute(
      '''
      INSERT INTO nodes (
        id, path, name, parent_path, type, content,
        created_at, updated_at, worktree
      )
      VALUES (?, '/', '/', NULL, 'directory', NULL, ?, ?, ?)
      ''',
      [_uuid.v4(), now, now, worktree],
    );
  }

  Future<void> _ensureDirectory(
    SqliteWriteContext tx,
    String path,
    String worktree,
  ) async {
    final normalized = _normalizePath(path);
    if (normalized == '/') {
      await _ensureWorktreeRoot(tx, worktree);
      return;
    }

    await _ensureWorktreeRoot(tx, worktree);
    final segments = _splitPath(normalized);
    var currentPath = '/';

    for (final segment in segments) {
      final nextPath = _joinPath(currentPath, segment);
      final exists = await tx.getOptional(
        'SELECT id FROM nodes WHERE worktree = ? AND path = ?',
        [worktree, nextPath],
      );

      if (exists == null) {
        final now = _timestamp();
        await tx.execute(
          '''
          INSERT INTO nodes (
            id, path, name, parent_path, type, content,
            created_at, updated_at, worktree
          )
          VALUES (?, ?, ?, ?, 'directory', NULL, ?, ?, ?)
          ''',
          [
            _uuid.v4(),
            nextPath,
            segment,
            currentPath,
            now,
            now,
            worktree,
          ],
        );
      }

      currentPath = nextPath;
    }
  }

  Future<void> _assertDirectoryExists(String path, String worktree) async {
    final row = await _db.getOptional(
      '''
      SELECT type FROM nodes WHERE worktree = ? AND path = ?
      ''',
      [worktree, path],
    );

    if (row != null && (row['type'] as String) == 'directory') {
      return;
    }

    if (path == '/') {
      await _db.writeTransaction((tx) async {
        await _ensureWorktreeRoot(tx, worktree);
      });
      final root = await _db.getOptional(
        '''
        SELECT type FROM nodes WHERE worktree = ? AND path = ?
        ''',
        [worktree, path],
      );
      if (root != null && (root['type'] as String) == 'directory') {
        return;
      }
    }

    throw StorageException('No directory found at $path');
  }

  VirtualEntry _rowToEntry(sqlite.Row row) {
    final type = NodeType.values.firstWhere(
      (value) => value.name == row['type'] as String,
    );
    final content = row['content'];

    return VirtualEntry(
      id: row['id'] as String,
      path: row['path'] as String,
      name: row['name'] as String,
      parentPath: row['parent_path'] as String?,
      type: type,
      content: content == null
          ? null
          : Uint8List.fromList(List<int>.from(content as List<int>)),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      worktree: row['worktree'] as String,
    );
  }

  int _timestamp() => DateTime.now().millisecondsSinceEpoch;

  String _normalizeWorktree(String? worktree) =>
      worktree == null ? '' : worktree.trim();

  String _normalizePath(String input) {
    var path = input.trim();
    if (path.isEmpty) {
      throw StorageException('Path cannot be empty');
    }

    path = path.replaceAll(RegExp(r'/+'), '/');
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.contains('..')) {
      throw StorageException('Relative path segments are not supported: $path');
    }
    return path;
  }

  String _normalizeName(String input) {
    final name = input.trim();
    if (name.isEmpty) {
      throw StorageException('Name cannot be empty');
    }
    if (name.contains('/')) {
      throw StorageException('Name cannot contain "/" characters');
    }
    if (name == '.') {
      throw StorageException('Name cannot be "."');
    }
    return name;
  }

  String _basename(String path) {
    if (path == '/') return '/';
    final index = path.lastIndexOf('/');
    return index == -1 ? path : path.substring(index + 1);
  }

  String? _parentPath(String path) {
    if (path == '/') return null;
    final index = path.lastIndexOf('/');
    if (index <= 0) return '/';
    return path.substring(0, index);
  }

  String _joinPath(String parent, String name) {
    if (parent == '/' || parent.isEmpty) {
      return '/$name';
    }
    return '$parent/$name';
  }

  List<String> _splitPath(String path) {
    if (path == '/' || path.isEmpty) {
      return const [];
    }
    return path.substring(1).split('/');
  }
}
