// Copyright (c) 2025, ThreadBox MCP contributors.
//
// Storage layer for ThreadBox using sqlite_async with UUID-based addressing.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
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
    this.version,
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
  final int? version;
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
      if (version != null) 'version': version,
      if (includeContent && content != null)
        'content': base64Encode(content!),
    };
  }
}

/// Represents a historical version of a file.
class FileVersion {
  FileVersion({
    required this.id,
    required this.nodeId,
    required this.version,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String nodeId;
  final int version;
  final Uint8List content;
  final DateTime createdAt;
}

/// Organized listing of a directory.
class DirectoryListing {
  const DirectoryListing({required this.directories, required this.files});

  final List<VirtualEntry> directories;
  final List<VirtualEntry> files;
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
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          worktree TEXT NOT NULL DEFAULT '',
          latest_version INTEGER
        )
      ''');

      await tx.execute('''
        CREATE TABLE IF NOT EXISTS file_versions (
          id TEXT PRIMARY KEY,
          node_id TEXT NOT NULL,
          version INTEGER NOT NULL,
          content BLOB NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(node_id) REFERENCES nodes(id)
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

      await tx.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_versions_node_version
        ON file_versions(node_id, version)
      ''');

      await _ensureWorktreeRoot(tx, '');
    });
  }

  /// Writes a file at [path] with [content], preserving version history.
  Future<VirtualEntry> writeFile(
    String path,
    List<int> content, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(path);
    final parent = _parentPath(normalizedPath);
    final now = _timestamp();
    final bytes = Uint8List.fromList(List<int>.from(content));

    return _db.writeTransaction((tx) async {
      await _ensureWorktreeRoot(tx, worktree);
      if (parent != null) {
        await _ensureDirectory(tx, parent, worktree);
      }

      final existing = await tx.getOptional(
        'SELECT * FROM nodes WHERE worktree = ? AND path = ?',
        [worktree, normalizedPath],
      );

      String nodeId;
      int nextVersion;

      if (existing == null) {
        nodeId = _uuid.v4();
        nextVersion = 1;
        await tx.execute(
          '''
          INSERT INTO nodes (
            id, path, name, parent_path, type, created_at, updated_at, worktree, latest_version
          )
          VALUES (?, ?, ?, ?, 'file', ?, ?, ?, ?)
          ''',
          [
            nodeId,
            normalizedPath,
            _basename(normalizedPath),
            parent,
            now,
            now,
            worktree,
            nextVersion,
          ],
        );
      } else {
        if ((existing['type'] as String) != 'file') {
          throw StorageException('Cannot overwrite directory $normalizedPath');
        }

        nodeId = existing['id'] as String;
        final currentVersion = existing['latest_version'] as int? ?? 0;
        nextVersion = currentVersion + 1;
        await tx.execute(
          '''
          UPDATE nodes
          SET updated_at = ?, latest_version = ?
          WHERE id = ?
          ''',
          [now, nextVersion, nodeId],
        );
      }

      await tx.execute(
        '''
        INSERT INTO file_versions (id, node_id, version, content, created_at)
        VALUES (?, ?, ?, ?, ?)
        ''',
        [_uuid.v4(), nodeId, nextVersion, bytes, now],
      );

      final row = await tx.get(
        '''
        SELECT n.*, v.content
        FROM nodes n
        JOIN file_versions v ON v.node_id = n.id AND v.version = n.latest_version
        WHERE n.id = ?
        ''',
        [nodeId],
      );

      return _rowToEntry(row);
    });
  }

  /// Reads the latest version of the file at [path].
  Future<VirtualEntry?> readFile(
    String path, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(path);

    final row = await _db.getOptional(
      '''
      SELECT n.*, v.content
      FROM nodes n
      JOIN file_versions v ON v.node_id = n.id AND v.version = n.latest_version
      WHERE n.worktree = ? AND n.path = ? AND n.type = 'file'
      ''',
      [worktree, normalizedPath],
    );

    if (row == null) return null;
    return _rowToEntry(row);
  }

  /// Lists the direct children of [dirPath].
  Future<DirectoryListing> listDirectory(
    String dirPath, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(dirPath);

    await _assertDirectoryExists(normalizedPath, worktree);

    final rows = await _db.getAll(
      '''
      SELECT n.*, v.content
      FROM nodes n
      LEFT JOIN file_versions v
        ON v.node_id = n.id AND v.version = n.latest_version
      WHERE n.worktree = ? AND n.parent_path = ?
      ORDER BY n.type DESC, n.name ASC
      ''',
      [worktree, normalizedPath == '/' ? '/' : normalizedPath],
    );

    final entries = rows.map(_rowToEntry).toList();
    final directories =
        entries.where((entry) => entry.type == NodeType.directory).toList();
    final files =
        entries.where((entry) => entry.type == NodeType.file).toList();
    return DirectoryListing(directories: directories, files: files);
  }

  /// Renames a file to [newName] within the same directory.
  Future<VirtualEntry> renameNode(
    String path,
    String newName, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(path);
    final normalizedName = _normalizeName(newName);
    final parent = _parentPath(normalizedPath);
    if (parent == null) {
      throw StorageException('Cannot rename the root directory');
    }

    final targetPath = _joinPath(parent, normalizedName);
    return _moveOrRename(normalizedPath, targetPath, worktree);
  }

  /// Moves a node to [targetDirectory].
  Future<VirtualEntry> moveNode(
    String path,
    String targetDirectory, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(path);
    final normalizedTargetDir = _normalizePath(targetDirectory);
    if (normalizedTargetDir == normalizedPath) {
      throw StorageException('Destination directory matches the file path');
    }
    final name = _basename(normalizedPath);
    final targetPath = _joinPath(normalizedTargetDir, name);
    return _moveOrRename(normalizedPath, targetPath, worktree);
  }

  /// Exports all files for [sessionId] to a ZIP archive.
  Future<String> exportSessionZip(
    String? sessionId, {
    String? destinationDir,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final rows = await _db.getAll(
      '''
      SELECT n.path, v.content
      FROM nodes n
      JOIN file_versions v ON v.node_id = n.id AND v.version = n.latest_version
      WHERE n.worktree = ? AND n.type = 'file'
      ORDER BY n.path
      ''',
      [worktree],
    );

    final archive = Archive();
    for (final row in rows) {
      final fullPath = row['path'] as String;
      final content = _toBytes(row['content']);
      final relativePath =
          fullPath.startsWith('/') ? fullPath.substring(1) : fullPath;
      archive.addFile(ArchiveFile(relativePath, content.length, content));
    }

    final encoder = ZipEncoder();
    final encoded = encoder.encode(archive) ?? Uint8List(0);

    final root = destinationDir == null
        ? Directory.systemTemp
        : Directory(destinationDir);
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }

    final safeSession =
        worktree.isEmpty ? 'default' : _sanitizeFileName(worktree);
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final filename = 'threadbox-session-$safeSession-$timestamp.zip';
    final outputPath = p.join(root.path, filename);
    final file = File(outputPath)..writeAsBytesSync(encoded, flush: true);
    return file.path;
  }

  /// Returns the full history for a file at [path].
  Future<List<FileVersion>> getFileHistory(
    String path, {
    String? sessionId,
  }) async {
    final worktree = _normalizeWorktree(sessionId);
    final normalizedPath = _normalizePath(path);

    final node = await _db.getOptional(
      '''
      SELECT id
      FROM nodes
      WHERE worktree = ? AND path = ? AND type = 'file'
      ''',
      [worktree, normalizedPath],
    );
    if (node == null) return const [];

    final rows = await _db.getAll(
      '''
      SELECT *
      FROM file_versions
      WHERE node_id = ?
      ORDER BY version DESC
      ''',
      [node['id'] as String],
    );

    return rows
        .map(
          (row) => FileVersion(
            id: row['id'] as String,
            nodeId: row['node_id'] as String,
            version: row['version'] as int,
            content: _toBytes(row['content']),
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
          ),
        )
        .toList();
  }

  /// Closes the underlying sqlite database connections.
  Future<void> close() => _db.close();

  Future<VirtualEntry> _moveOrRename(
    String fromPath,
    String toPath,
    String worktree,
  ) async {
    if (fromPath == '/') {
      throw StorageException('Cannot move the root directory');
    }

    final newParent = _parentPath(toPath);
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

      if ((source['type'] as String) != 'file') {
        throw StorageException(
          'Only file nodes can be moved or renamed currently',
        );
      }

      final conflict = await tx.getOptional(
        'SELECT id FROM nodes WHERE worktree = ? AND path = ?',
        [worktree, toPath],
      );
      if (conflict != null) {
        throw StorageException('A node already exists at $toPath');
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
          toPath,
          _basename(toPath),
          newParent,
          now,
          source['id'] as String,
        ],
      );

      final row = await tx.get(
        '''
        SELECT n.*, v.content
        FROM nodes n
        LEFT JOIN file_versions v
          ON v.node_id = n.id AND v.version = n.latest_version
        WHERE n.id = ?
        ''',
        [source['id'] as String],
      );

      return _rowToEntry(row);
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
        id, path, name, parent_path, type, created_at, updated_at, worktree, latest_version
      )
      VALUES (?, '/', '/', NULL, 'directory', ?, ?, ?, NULL)
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
            id, path, name, parent_path, type, created_at, updated_at, worktree, latest_version
          )
          VALUES (?, ?, ?, ?, 'directory', ?, ?, ?, NULL)
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
      version: row['latest_version'] as int?,
      content: content == null ? null : _toBytes(content),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      worktree: row['worktree'] as String,
    );
  }

  Uint8List _toBytes(Object value) {
    if (value is Uint8List) {
      return Uint8List.fromList(value);
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    throw StateError('Unexpected BLOB value type: ${value.runtimeType}');
  }

  int _timestamp() => DateTime.now().millisecondsSinceEpoch;

  String _normalizeWorktree(String? worktree) =>
      worktree == null ? '' : worktree.trim();

  String _normalizePath(String input) {
    var normalized = input.trim();
    if (normalized.isEmpty) {
      throw StorageException('Path cannot be empty');
    }

    normalized = normalized.replaceAll(RegExp(r'/+'), '/');
    if (!normalized.startsWith('/')) {
      normalized = '/$normalized';
    }
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    if (normalized.contains('..')) {
      throw StorageException(
        'Relative path segments are not supported: $normalized',
      );
    }
    return normalized;
  }

  String _normalizeName(String input) {
    final name = input.trim();
    if (name.isEmpty) {
      throw StorageException('Name cannot be empty');
    }
    if (name.contains('/')) {
      throw StorageException('Name cannot contain "/" characters');
    }
    if (name == '.' || name == '..') {
      throw StorageException('Name cannot be "." or ".."');
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

  String _sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[^A-Za-z0-9_\-]+'), '-');
  }
}
