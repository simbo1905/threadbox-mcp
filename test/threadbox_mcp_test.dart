// Copyright (c) 2025, ThreadBox MCP contributors.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

void main() {
  late FileStorage storage;
  late String tempDbPath;

  setUp(() async {
    // Create a temporary database for each test
    tempDbPath = '${Directory.systemTemp.path}/threadbox_test_${DateTime.now().millisecondsSinceEpoch}.db';
    storage = await FileStorage.create(tempDbPath);
  });

  tearDown(() async {
    // Clean up
    await storage.close();
    final dbFile = File(tempDbPath);
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
  });

  group('Basic FileStorage Operations', () {
    test('writeFile stores content with UUID pk', () async {
      final content = utf8.encode('Hello, World!');
      final id = await storage.writeFile('/test/file.txt', content);

      expect(id, isNotNull);
      expect(id.length, equals(36)); // UUID v4 length
    });

    test('readFile retrieves latest version', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/test/file.txt', content1);
      await storage.writeFile('/test/file.txt', content2);

      final record = await storage.readFile('/test/file.txt');

      expect(record, isNotNull);
      expect(record!.version, equals(2));
      expect(utf8.decode(record.content), equals('Version 2'));
    });

    test('readFile returns null for non-existent file', () async {
      final record = await storage.readFile('/non/existent.txt');
      expect(record, isNull);
    });

    test('UUID primary key is unique for each write', () async {
      final content = utf8.encode('Same content');

      final id1 = await storage.writeFile('/test/file.txt', content);
      final id2 = await storage.writeFile('/test/file.txt', content);

      expect(id1, isNot(equals(id2)));
    });

    test('writeFile with custom metadata', () async {
      final content = utf8.encode('Test content');
      final metadata = '{"author": "test", "tags": ["important"]}';
      
      await storage.writeFile('/test/file.txt', content, metadata: metadata);
      final record = await storage.readFile('/test/file.txt');

      expect(record, isNotNull);
      expect(record!.metadata, equals(metadata));
    });
  });

  group('Directory Operations', () {
    test('createDirectory creates a directory entry', () async {
      final id = await storage.createDirectory('/test/dir');

      expect(id, isNotNull);
      final record = await storage.readFile('/test/dir/');
      expect(record, isNotNull);
      expect(record!.isDirectory, isTrue);
    });

    test('createDirectory with metadata', () async {
      final metadata = '{"description": "test directory"}';
      await storage.createDirectory('/test/dir', metadata: metadata);

      final record = await storage.readFile('/test/dir/');
      expect(record, isNotNull);
      expect(record!.metadata, equals(metadata));
    });

    test('listDirectory returns files in directory (non-recursive)', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content);
      await storage.writeFile('/dir/file2.txt', content);
      await storage.writeFile('/dir/subdir/file3.txt', content);
      await storage.writeFile('/other/file4.txt', content);

      final files = await storage.listDirectory('/dir');

      expect(files.length, equals(2));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/file2.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/subdir/file3.txt'), isFalse);
    });

    test('listDirectory returns files recursively', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content);
      await storage.writeFile('/dir/subdir/file2.txt', content);
      await storage.writeFile('/dir/subdir/deep/file3.txt', content);

      final files = await storage.listDirectory('/dir', recursive: true);

      expect(files.length, greaterThanOrEqualTo(3));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/subdir/file2.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/subdir/deep/file3.txt'), isTrue);
    });

    test('listDirectory returns empty list for empty directory', () async {
      await storage.createDirectory('/empty/dir');
      final files = await storage.listDirectory('/empty/dir');

      expect(files, isEmpty);
    });
  });

  group('File Operations', () {
    test('moveFile moves a file to new location', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content);

      await storage.moveFile('/test/file.txt', '/moved/file.txt');

      final oldFile = await storage.readFile('/test/file.txt');
      final newFile = await storage.readFile('/moved/file.txt');

      expect(oldFile, isNull);
      expect(newFile, isNotNull);
      expect(utf8.decode(newFile!.content), equals('Test content'));
    });

    test('moveFile moves directory and all contents', () async {
      final content = utf8.encode('Test');
      await storage.createDirectory('/test/dir');
      await storage.writeFile('/test/dir/file1.txt', content);
      await storage.writeFile('/test/dir/subdir/file2.txt', content);

      await storage.moveFile('/test/dir', '/moved/dir');

      final oldDir = await storage.readFile('/test/dir/');
      final newDir = await storage.readFile('/moved/dir/');
      final movedFile = await storage.readFile('/moved/dir/file1.txt');

      expect(oldDir, isNull);
      expect(newDir, isNotNull);
      expect(newDir!.isDirectory, isTrue);
      expect(movedFile, isNotNull);
    });

    test('moveFile throws error for non-existent source', () async {
      expect(
        () => storage.moveFile('/non/existent.txt', '/dest.txt'),
        throwsException,
      );
    });

    test('renameFile renames a file', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/oldname.txt', content);

      await storage.renameFile('/test/oldname.txt', 'newname.txt');

      final oldFile = await storage.readFile('/test/oldname.txt');
      final newFile = await storage.readFile('/test/newname.txt');

      expect(oldFile, isNull);
      expect(newFile, isNotNull);
      expect(utf8.decode(newFile!.content), equals('Test content'));
    });

    test('copyFile creates a copy of a file', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/original.txt', content);

      await storage.copyFile('/test/original.txt', '/test/copy.txt');

      final original = await storage.readFile('/test/original.txt');
      final copy = await storage.readFile('/test/copy.txt');

      expect(original, isNotNull);
      expect(copy, isNotNull);
      expect(utf8.decode(original!.content), equals('Test content'));
      expect(utf8.decode(copy!.content), equals('Test content'));
      expect(original.id, isNot(equals(copy.id)));
    });

    test('copyFile copies directory and all contents', () async {
      final content = utf8.encode('Test');
      await storage.createDirectory('/test/dir');
      await storage.writeFile('/test/dir/file1.txt', content);
      await storage.writeFile('/test/dir/subdir/file2.txt', content);

      await storage.copyFile('/test/dir', '/test/copy');

      final original = await storage.readFile('/test/dir/');
      final copy = await storage.readFile('/test/copy/');
      final copiedFile = await storage.readFile('/test/copy/file1.txt');

      expect(original, isNotNull);
      expect(copy, isNotNull);
      expect(copy!.isDirectory, isTrue);
      expect(copiedFile, isNotNull);
    });

    test('deleteFile marks file as deleted', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content);

      await storage.deleteFile('/test/file.txt');

      final file = await storage.readFile('/test/file.txt');
      expect(file, isNull);
    });

    test('deleteFile rejects non-empty directory without recursive flag', () async {
      final content = utf8.encode('Test');
      await storage.createDirectory('/test/dir');
      await storage.writeFile('/test/dir/file.txt', content);

      expect(
        () => storage.deleteFile('/test/dir', recursive: false),
        throwsException,
      );
    });

    test('deleteFile with recursive deletes directory and contents', () async {
      final content = utf8.encode('Test');
      await storage.createDirectory('/test/dir');
      await storage.writeFile('/test/dir/file1.txt', content);
      await storage.writeFile('/test/dir/subdir/file2.txt', content);

      await storage.deleteFile('/test/dir', recursive: true);

      final dir = await storage.readFile('/test/dir/');
      final file1 = await storage.readFile('/test/dir/file1.txt');
      final file2 = await storage.readFile('/test/dir/subdir/file2.txt');

      expect(dir, isNull);
      expect(file1, isNull);
      expect(file2, isNull);
    });
  });

  group('Metadata Operations', () {
    test('getMetadata returns file metadata', () async {
      final content = utf8.encode('Test content with 20 bytes!');
      await storage.writeFile('/test/file.txt', content);

      final metadata = await storage.getMetadata('/test/file.txt');

      expect(metadata, isNotNull);
      expect(metadata!.path, equals('/test/file.txt'));
      expect(metadata.isDirectory, isFalse);
      expect(metadata.size, equals(content.length));
      expect(metadata.version, equals(1));
      expect(metadata.childCount, isNull);
    });

    test('getMetadata returns directory metadata with child count', () async {
      final content = utf8.encode('Test');
      await storage.createDirectory('/test/dir');
      await storage.writeFile('/test/dir/file1.txt', content);
      await storage.writeFile('/test/dir/file2.txt', content);

      final metadata = await storage.getMetadata('/test/dir');

      expect(metadata, isNotNull);
      expect(metadata!.isDirectory, isTrue);
      expect(metadata.childCount, equals(2));
    });

    test('getMetadata returns null for non-existent path', () async {
      final metadata = await storage.getMetadata('/non/existent.txt');
      expect(metadata, isNull);
    });

    test('getMetadata includes custom metadata', () async {
      final content = utf8.encode('Test');
      final customMetadata = '{"tag": "important"}';
      await storage.writeFile('/test/file.txt', content, metadata: customMetadata);

      final metadata = await storage.getMetadata('/test/file.txt');

      expect(metadata, isNotNull);
      expect(metadata!.customMetadata, equals(customMetadata));
    });
  });

  group('Version History', () {
    test('getFileHistory returns all versions', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');
      final content3 = utf8.encode('Version 3');

      await storage.writeFile('/test/file.txt', content1);
      await storage.writeFile('/test/file.txt', content2);
      await storage.writeFile('/test/file.txt', content3);

      final history = await storage.getFileHistory('/test/file.txt');

      expect(history.length, equals(3));
      expect(history[0].version, equals(3)); // Most recent first
      expect(history[1].version, equals(2));
      expect(history[2].version, equals(1));
    });

    test('getFileHistory includes deleted versions', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content);
      await storage.deleteFile('/test/file.txt');

      final history = await storage.getFileHistory('/test/file.txt');

      expect(history.length, equals(2)); // Original + deletion marker
    });

    test('getFileHistory returns empty list for non-existent file', () async {
      final history = await storage.getFileHistory('/non/existent.txt');
      expect(history, isEmpty);
    });
  });

  group('Worktree Isolation', () {
    test('files in different worktrees are isolated', () async {
      final content1 = utf8.encode('Worktree 1 content');
      final content2 = utf8.encode('Worktree 2 content');

      await storage.writeFile('/test/file.txt', content1, worktree: 'wt1');
      await storage.writeFile('/test/file.txt', content2, worktree: 'wt2');

      final record1 = await storage.readFile('/test/file.txt', worktree: 'wt1');
      final record2 = await storage.readFile('/test/file.txt', worktree: 'wt2');

      expect(record1, isNotNull);
      expect(record2, isNotNull);
      expect(utf8.decode(record1!.content), equals('Worktree 1 content'));
      expect(utf8.decode(record2!.content), equals('Worktree 2 content'));
    });

    test('listDirectory respects worktree isolation', () async {
      final content = utf8.encode('Test');

      await storage.writeFile('/dir/file1.txt', content, worktree: 'wt1');
      await storage.writeFile('/dir/file2.txt', content, worktree: 'wt1');
      await storage.writeFile('/dir/file3.txt', content, worktree: 'wt2');

      final files1 = await storage.listDirectory('/dir', worktree: 'wt1');
      final files2 = await storage.listDirectory('/dir', worktree: 'wt2');

      expect(files1.length, equals(2));
      expect(files2.length, equals(1));
    });

    test('moveFile respects worktree isolation', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content, worktree: 'wt1');
      await storage.writeFile('/test/file.txt', content, worktree: 'wt2');

      await storage.moveFile('/test/file.txt', '/moved/file.txt', worktree: 'wt1');

      final wt1Old = await storage.readFile('/test/file.txt', worktree: 'wt1');
      final wt1New = await storage.readFile('/moved/file.txt', worktree: 'wt1');
      final wt2File = await storage.readFile('/test/file.txt', worktree: 'wt2');

      expect(wt1Old, isNull);
      expect(wt1New, isNotNull);
      expect(wt2File, isNotNull); // wt2 file should be unaffected
    });

    test('deleteFile respects worktree isolation', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content, worktree: 'wt1');
      await storage.writeFile('/test/file.txt', content, worktree: 'wt2');

      await storage.deleteFile('/test/file.txt', worktree: 'wt1');

      final wt1File = await storage.readFile('/test/file.txt', worktree: 'wt1');
      final wt2File = await storage.readFile('/test/file.txt', worktree: 'wt2');

      expect(wt1File, isNull);
      expect(wt2File, isNotNull);
    });

    test('listWorktrees returns all worktrees', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/file.txt', content, worktree: 'worktree-1');
      await storage.writeFile('/file.txt', content, worktree: 'worktree-2');
      await storage.writeFile('/file.txt', content, worktree: 'worktree-3');

      final worktrees = await storage.listWorktrees();

      expect(worktrees.length, equals(3));
      expect(worktrees, contains('worktree-1'));
      expect(worktrees, contains('worktree-2'));
      expect(worktrees, contains('worktree-3'));
    });

    test('listWorktrees excludes deleted files', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/file.txt', content, worktree: 'wt1');
      await storage.writeFile('/file.txt', content, worktree: 'wt2');
      await storage.deleteFile('/file.txt', worktree: 'wt1');

      final worktrees = await storage.listWorktrees();

      expect(worktrees, contains('wt2'));
      expect(worktrees, isNot(contains('wt1')));
    });
  });

  group('Path Utilities', () {
    test('exists returns true for existing file', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/test/file.txt', content);

      final exists = await storage.exists('/test/file.txt');
      expect(exists, isTrue);
    });

    test('exists returns true for existing directory', () async {
      await storage.createDirectory('/test/dir');

      final exists = await storage.exists('/test/dir/');
      expect(exists, isTrue);
    });

    test('exists returns false for non-existent path', () async {
      final exists = await storage.exists('/non/existent.txt');
      expect(exists, isFalse);
    });

    test('exists returns false for deleted file', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/test/file.txt', content);
      await storage.deleteFile('/test/file.txt');

      final exists = await storage.exists('/test/file.txt');
      expect(exists, isFalse);
    });

    test('exists respects worktree isolation', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/test/file.txt', content, worktree: 'wt1');

      final existsWt1 = await storage.exists('/test/file.txt', worktree: 'wt1');
      final existsWt2 = await storage.exists('/test/file.txt', worktree: 'wt2');

      expect(existsWt1, isTrue);
      expect(existsWt2, isFalse);
    });
  });

  group('Edge Cases and Error Handling', () {
    test('handles files with special characters in path', () async {
      final content = utf8.encode('Test');
      final specialPath = '/test/file with spaces & special!chars.txt';
      
      await storage.writeFile(specialPath, content);
      final record = await storage.readFile(specialPath);

      expect(record, isNotNull);
      expect(record!.path, equals(specialPath));
    });

    test('handles empty file content', () async {
      final emptyContent = <int>[];
      await storage.writeFile('/test/empty.txt', emptyContent);

      final record = await storage.readFile('/test/empty.txt');
      expect(record, isNotNull);
      expect(record!.content, isEmpty);
    });

    test('handles very long file paths', () async {
      final content = utf8.encode('Test');
      final longPath = '/a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t/u/v/w/x/y/z/file.txt';
      
      await storage.writeFile(longPath, content);
      final record = await storage.readFile(longPath);

      expect(record, isNotNull);
    });

    test('handles large file content', () async {
      // Create 1MB of content
      final largeContent = List<int>.generate(1024 * 1024, (i) => i % 256);
      
      await storage.writeFile('/test/large.bin', largeContent);
      final record = await storage.readFile('/test/large.bin');

      expect(record, isNotNull);
      expect(record!.content.length, equals(1024 * 1024));
    });

    test('handles rapid successive writes', () async {
      final futures = <Future<String>>[];
      
      for (int i = 0; i < 10; i++) {
        final content = utf8.encode('Version $i');
        futures.add(storage.writeFile('/test/file.txt', content));
      }

      await Future.wait(futures);

      final history = await storage.getFileHistory('/test/file.txt');
      expect(history.length, equals(10));
    });

    test('copyFile throws error for non-existent source', () async {
      expect(
        () => storage.copyFile('/non/existent.txt', '/dest.txt'),
        throwsException,
      );
    });

    test('deleteFile throws error for non-existent path', () async {
      expect(
        () => storage.deleteFile('/non/existent.txt'),
        throwsException,
      );
    });
  });

  group('Complex Scenarios', () {
    test('move then copy preserves content correctly', () async {
      final content = utf8.encode('Original content');
      await storage.writeFile('/test/file.txt', content);

      await storage.moveFile('/test/file.txt', '/moved/file.txt');
      await storage.copyFile('/moved/file.txt', '/copied/file.txt');

      final moved = await storage.readFile('/moved/file.txt');
      final copied = await storage.readFile('/copied/file.txt');

      expect(moved, isNotNull);
      expect(copied, isNotNull);
      expect(utf8.decode(moved!.content), equals('Original content'));
      expect(utf8.decode(copied!.content), equals('Original content'));
    });

    test('rename preserves file history', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/test/oldname.txt', content1);
      await storage.writeFile('/test/oldname.txt', content2);
      await storage.renameFile('/test/oldname.txt', 'newname.txt');

      final oldHistory = await storage.getFileHistory('/test/oldname.txt');
      final newFile = await storage.readFile('/test/newname.txt');

      expect(oldHistory.length, equals(3)); // 2 writes + 1 delete marker
      expect(newFile, isNotNull);
      expect(utf8.decode(newFile!.content), equals('Version 2'));
    });

    test('nested directory operations work correctly', () async {
      final content = utf8.encode('Test');

      // Create nested structure
      await storage.createDirectory('/a');
      await storage.createDirectory('/a/b');
      await storage.createDirectory('/a/b/c');
      await storage.writeFile('/a/b/c/file.txt', content);

      // Move nested directory
      await storage.moveFile('/a/b', '/moved/b');

      final oldPath = await storage.readFile('/a/b/c/file.txt');
      final newPath = await storage.readFile('/moved/b/c/file.txt');

      expect(oldPath, isNull);
      expect(newPath, isNotNull);
    });

    test('concurrent operations on different paths work correctly', () async {
      final content = utf8.encode('Test');

      final futures = <Future>[];
      for (int i = 0; i < 10; i++) {
        futures.add(storage.writeFile('/test/file$i.txt', content));
      }

      await Future.wait(futures);

      final files = await storage.listDirectory('/test', recursive: true);
      expect(files.length, equals(10));
    });
  });
}
