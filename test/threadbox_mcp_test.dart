// Copyright (c) 2025, ThreadBox MCP contributors.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

void main() {
  late FileStorage storage;
  late String tempDbPath;

  setUp(() {
    // Create a temporary database for each test
    tempDbPath = '${Directory.systemTemp.path}/threadbox_test_${DateTime.now().millisecondsSinceEpoch}.db';
    storage = FileStorage(tempDbPath);
  });

  tearDown(() async {
    // Clean up
    await storage.close();
    final dbFile = File(tempDbPath);
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
  });

  group('FileStorage', () {
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
      final record = await storage.readFile('/nonexistent/file.txt');

      expect(record, isNull);
    });

    test('listDirectory returns files in directory', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content);
      await storage.writeFile('/dir/file2.txt', content);
      await storage.writeFile('/other/file3.txt', content);

      final files = await storage.listDirectory('/dir');

      expect(files.length, equals(2));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/file2.txt'), isTrue);
      expect(files.any((f) => f.path == '/other/file3.txt'), isFalse);
    });

    test('listDirectory handles trailing slash correctly', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content);
      await storage.writeFile('/dir/file2.txt', content);

      final files1 = await storage.listDirectory('/dir');
      final files2 = await storage.listDirectory('/dir/');

      expect(files1.length, equals(2));
      expect(files2.length, equals(2));
    });

    test('listDirectory returns empty list for non-existent directory', () async {
      final files = await storage.listDirectory('/nonexistent');

      expect(files, isEmpty);
    });

    test('worktree isolation works correctly', () async {
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

    test('worktree isolation in listDirectory', () async {
      final content1 = utf8.encode('Worktree 1');
      final content2 = utf8.encode('Worktree 2');

      await storage.writeFile('/dir/file.txt', content1, worktree: 'wt1');
      await storage.writeFile('/dir/file.txt', content2, worktree: 'wt2');

      final files1 = await storage.listDirectory('/dir', worktree: 'wt1');
      final files2 = await storage.listDirectory('/dir', worktree: 'wt2');

      expect(files1.length, equals(1));
      expect(files2.length, equals(1));
      expect(utf8.decode(files1.first.content), equals('Worktree 1'));
      expect(utf8.decode(files2.first.content), equals('Worktree 2'));
    });

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
      expect(utf8.decode(history[0].content), equals('Version 3'));
      expect(utf8.decode(history[1].content), equals('Version 2'));
      expect(utf8.decode(history[2].content), equals('Version 1'));
    });

    test('UUID primary key is unique for each write', () async {
      final content = utf8.encode('Same content');

      final id1 = await storage.writeFile('/test/file.txt', content);
      final id2 = await storage.writeFile('/test/file.txt', content);

      expect(id1, isNot(equals(id2)));
    });

    test('moveFile moves file to new path', () async {
      final content = utf8.encode('File content');
      final originalId = await storage.writeFile('/old/path/file.txt', content);

      final newId = await storage.moveFile('/old/path/file.txt', '/new/path/file.txt');

      // Original file should still exist (immutable)
      final oldFile = await storage.readFile('/old/path/file.txt');
      expect(oldFile, isNotNull);
      expect(oldFile!.id, equals(originalId));

      // New file should exist with same content
      final newFile = await storage.readFile('/new/path/file.txt');
      expect(newFile, isNotNull);
      expect(newFile!.id, equals(newId));
      expect(newFile.id, isNot(equals(originalId))); // New UUID
      expect(utf8.decode(newFile.content), equals(utf8.decode(oldFile.content)));
    });

    test('moveFile throws exception if source file does not exist', () async {
      expect(
        () => storage.moveFile('/nonexistent/file.txt', '/new/path/file.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('moveFile works with worktree isolation', () async {
      final content1 = utf8.encode('Worktree 1 content');
      final content2 = utf8.encode('Worktree 2 content');

      await storage.writeFile('/file.txt', content1, worktree: 'wt1');
      await storage.writeFile('/file.txt', content2, worktree: 'wt2');

      await storage.moveFile('/file.txt', '/moved.txt', worktree: 'wt1');

      // Check wt1 file was moved
      final moved1 = await storage.readFile('/moved.txt', worktree: 'wt1');
      expect(moved1, isNotNull);
      expect(utf8.decode(moved1!.content), equals('Worktree 1 content'));

      // Check wt2 file was not affected
      final original2 = await storage.readFile('/file.txt', worktree: 'wt2');
      expect(original2, isNotNull);
      expect(utf8.decode(original2!.content), equals('Worktree 2 content'));
    });

    test('renameFile renames file correctly', () async {
      final content = utf8.encode('File content');
      await storage.writeFile('/old_name.txt', content);

      final newId = await storage.renameFile('/old_name.txt', '/new_name.txt');

      // Old file should still exist (immutable)
      final oldFile = await storage.readFile('/old_name.txt');
      expect(oldFile, isNotNull);

      // New file should exist
      final newFile = await storage.readFile('/new_name.txt');
      expect(newFile, isNotNull);
      expect(newFile!.id, equals(newId));
      expect(utf8.decode(newFile.content), equals('File content'));
    });

    test('renameFile throws exception if source file does not exist', () async {
      expect(
        () => storage.renameFile('/nonexistent.txt', '/new_name.txt'),
        throwsA(isA<Exception>()),
      );
    });

    test('renameFile preserves version history', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/file.txt', content1);
      await storage.writeFile('/file.txt', content2);

      await storage.renameFile('/file.txt', '/renamed.txt');

      // Check history of original file
      final oldHistory = await storage.getFileHistory('/file.txt');
      expect(oldHistory.length, equals(2));

      // Check renamed file has new version
      final renamedFile = await storage.readFile('/renamed.txt');
      expect(renamedFile, isNotNull);
      expect(renamedFile!.version, equals(1)); // New file starts at version 1
      expect(utf8.decode(renamedFile.content), equals('Version 2'));
    });

    test('multiple operations maintain data integrity', () async {
      // Write multiple files
      await storage.writeFile('/dir1/file1.txt', utf8.encode('Content 1'));
      await storage.writeFile('/dir1/file2.txt', utf8.encode('Content 2'));
      await storage.writeFile('/dir2/file3.txt', utf8.encode('Content 3'));

      // Move a file
      await storage.moveFile('/dir1/file1.txt', '/dir2/file1.txt');

      // Rename a file
      await storage.renameFile('/dir2/file3.txt', '/dir2/file3_renamed.txt');

      // Verify final state
      final dir1Files = await storage.listDirectory('/dir1');
      final dir2Files = await storage.listDirectory('/dir2');

      expect(dir1Files.length, equals(1)); // Only file2 remains
      expect(dir1Files.first.path, equals('/dir1/file2.txt'));

      expect(dir2Files.length, equals(2)); // file1 moved here, file3 renamed
      expect(dir2Files.any((f) => f.path == '/dir2/file1.txt'), isTrue);
      expect(dir2Files.any((f) => f.path == '/dir2/file3_renamed.txt'), isTrue);
    });

    test('concurrent writes create separate versions', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');
      final content3 = utf8.encode('Version 3');

      // Write multiple versions
      await Future.wait([
        storage.writeFile('/concurrent.txt', content1),
        Future.delayed(Duration(milliseconds: 10), () => storage.writeFile('/concurrent.txt', content2)),
        Future.delayed(Duration(milliseconds: 20), () => storage.writeFile('/concurrent.txt', content3)),
      ]);

      final history = await storage.getFileHistory('/concurrent.txt');
      expect(history.length, equals(3));
    });

    test('file paths are case sensitive', () async {
      await storage.writeFile('/File.txt', utf8.encode('Upper'));
      await storage.writeFile('/file.txt', utf8.encode('Lower'));

      final upper = await storage.readFile('/File.txt');
      final lower = await storage.readFile('/file.txt');

      expect(upper, isNotNull);
      expect(lower, isNotNull);
      expect(utf8.decode(upper!.content), equals('Upper'));
      expect(utf8.decode(lower!.content), equals('Lower'));
    });

    test('empty file content is handled correctly', () async {
      final id = await storage.writeFile('/empty.txt', []);

      expect(id, isNotNull);
      final record = await storage.readFile('/empty.txt');
      expect(record, isNotNull);
      expect(record!.content, isEmpty);
    });

    test('binary content is stored correctly', () async {
      final binaryContent = List.generate(256, (i) => i);
      final id = await storage.writeFile('/binary.bin', binaryContent);

      expect(id, isNotNull);
      final record = await storage.readFile('/binary.bin');
      expect(record, isNotNull);
      expect(record!.content, equals(binaryContent));
    });
  });

  group('MCP Tool Integration Tests', () {
    test('write_file tool functionality', () async {
      final content = utf8.encode('Test content');
      final id = await storage.writeFile('/test.txt', content);

      expect(id, isNotNull);
      expect(id.length, greaterThan(0));
    });

    test('read_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test.txt', content);

      final record = await storage.readFile('/test.txt');

      expect(record, isNotNull);
      expect(record!.path, equals('/test.txt'));
      expect(utf8.decode(record.content), equals('Test content'));
    });

    test('list_directory tool functionality', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/dir/file.txt', content);

      final files = await storage.listDirectory('/dir');

      expect(files, isNotEmpty);
      expect(files.first.path, equals('/dir/file.txt'));
    });

    test('move_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/source.txt', content);

      final newId = await storage.moveFile('/source.txt', '/dest.txt');

      expect(newId, isNotNull);
      final moved = await storage.readFile('/dest.txt');
      expect(moved, isNotNull);
      expect(utf8.decode(moved!.content), equals('Test content'));
    });

    test('rename_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/old.txt', content);

      final newId = await storage.renameFile('/old.txt', '/new.txt');

      expect(newId, isNotNull);
      final renamed = await storage.readFile('/new.txt');
      expect(renamed, isNotNull);
      expect(utf8.decode(renamed!.content), equals('Test content'));
    });
  });
}
