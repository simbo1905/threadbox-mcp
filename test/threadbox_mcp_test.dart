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
      final id = await storage.writeFile('/test/file.txt', content, sessionId: 'session1');

      expect(id, isNotNull);
      expect(id.length, equals(36)); // UUID v4 length
    });

    test('readFile retrieves latest version', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/test/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/test/file.txt', content2, sessionId: 'session1');

      final record = await storage.readFile('/test/file.txt', sessionId: 'session1');

      expect(record, isNotNull);
      expect(record!.version, equals(2));
      expect(utf8.decode(record.content), equals('Version 2'));
    });

    test('readFile returns null for non-existent file', () async {
      final record = await storage.readFile('/nonexistent/file.txt', sessionId: 'session1');

      expect(record, isNull);
    });

    test('listDirectory returns files in directory', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content, sessionId: 'session1');
      await storage.writeFile('/dir/file2.txt', content, sessionId: 'session1');
      await storage.writeFile('/other/file3.txt', content, sessionId: 'session1');

      final files = await storage.listDirectory('/dir', sessionId: 'session1');

      expect(files.length, equals(2));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/file2.txt'), isTrue);
      expect(files.any((f) => f.path == '/other/file3.txt'), isFalse);
    });

    test('listDirectory handles trailing slash correctly', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content, sessionId: 'session1');
      await storage.writeFile('/dir/file2.txt', content, sessionId: 'session1');

      final files1 = await storage.listDirectory('/dir', sessionId: 'session1');
      final files2 = await storage.listDirectory('/dir/', sessionId: 'session1');

      expect(files1.length, equals(2));
      expect(files2.length, equals(2));
    });

    test('listDirectory returns empty list for non-existent directory', () async {
      final files = await storage.listDirectory('/nonexistent', sessionId: 'session1');

      expect(files, isEmpty);
    });

    test('session isolation works correctly', () async {
      final content1 = utf8.encode('Session 1 content');
      final content2 = utf8.encode('Session 2 content');

      await storage.writeFile('/test/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/test/file.txt', content2, sessionId: 'session2');

      final record1 = await storage.readFile('/test/file.txt', sessionId: 'session1');
      final record2 = await storage.readFile('/test/file.txt', sessionId: 'session2');

      expect(record1, isNotNull);
      expect(record2, isNotNull);
      expect(utf8.decode(record1!.content), equals('Session 1 content'));
      expect(utf8.decode(record2!.content), equals('Session 2 content'));
    });

    test('session isolation in listDirectory', () async {
      final content1 = utf8.encode('Session 1');
      final content2 = utf8.encode('Session 2');

      await storage.writeFile('/dir/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/dir/file.txt', content2, sessionId: 'session2');

      final files1 = await storage.listDirectory('/dir', sessionId: 'session1');
      final files2 = await storage.listDirectory('/dir', sessionId: 'session2');

      expect(files1.length, equals(1));
      expect(files2.length, equals(1));
      expect(utf8.decode(files1.first.content), equals('Session 1'));
      expect(utf8.decode(files2.first.content), equals('Session 2'));
    });

    test('getFileHistory returns all versions', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');
      final content3 = utf8.encode('Version 3');

      await storage.writeFile('/test/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/test/file.txt', content2, sessionId: 'session1');
      await storage.writeFile('/test/file.txt', content3, sessionId: 'session1');

      final history = await storage.getFileHistory('/test/file.txt', sessionId: 'session1');

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

      final id1 = await storage.writeFile('/test/file.txt', content, sessionId: 'session1');
      final id2 = await storage.writeFile('/test/file.txt', content, sessionId: 'session1');

      expect(id1, isNot(equals(id2)));
    });

    test('moveFile moves file to new path', () async {
      final content = utf8.encode('File content');
      final originalId = await storage.writeFile('/old/path/file.txt', content, sessionId: 'session1');

      final newId = await storage.moveFile('/old/path/file.txt', '/new/path/file.txt', sessionId: 'session1');

      // Original file should still exist (immutable)
      final oldFile = await storage.readFile('/old/path/file.txt', sessionId: 'session1');
      expect(oldFile, isNotNull);
      expect(oldFile!.id, equals(originalId));

      // New file should exist with same content
      final newFile = await storage.readFile('/new/path/file.txt', sessionId: 'session1');
      expect(newFile, isNotNull);
      expect(newFile!.id, equals(newId));
      expect(newFile.id, isNot(equals(originalId))); // New UUID
      expect(utf8.decode(newFile.content), equals(utf8.decode(oldFile.content)));
    });

    test('moveFile throws exception if source file does not exist', () async {
      expect(
        () => storage.moveFile('/nonexistent/file.txt', '/new/path/file.txt', sessionId: 'session1'),
        throwsA(isA<Exception>()),
      );
    });

    test('moveFile works with session isolation', () async {
      final content1 = utf8.encode('Session 1 content');
      final content2 = utf8.encode('Session 2 content');

      await storage.writeFile('/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/file.txt', content2, sessionId: 'session2');

      await storage.moveFile('/file.txt', '/moved.txt', sessionId: 'session1');

      // Check session1 file was moved
      final moved1 = await storage.readFile('/moved.txt', sessionId: 'session1');
      expect(moved1, isNotNull);
      expect(utf8.decode(moved1!.content), equals('Session 1 content'));

      // Check session2 file was not affected
      final original2 = await storage.readFile('/file.txt', sessionId: 'session2');
      expect(original2, isNotNull);
      expect(utf8.decode(original2!.content), equals('Session 2 content'));
    });

    test('renameFile renames file correctly', () async {
      final content = utf8.encode('File content');
      await storage.writeFile('/old_name.txt', content, sessionId: 'session1');

      final newId = await storage.renameFile('/old_name.txt', '/new_name.txt', sessionId: 'session1');

      // Old file should still exist (immutable)
      final oldFile = await storage.readFile('/old_name.txt', sessionId: 'session1');
      expect(oldFile, isNotNull);

      // New file should exist
      final newFile = await storage.readFile('/new_name.txt', sessionId: 'session1');
      expect(newFile, isNotNull);
      expect(newFile!.id, equals(newId));
      expect(utf8.decode(newFile.content), equals('File content'));
    });

    test('renameFile throws exception if source file does not exist', () async {
      expect(
        () => storage.renameFile('/nonexistent.txt', '/new_name.txt', sessionId: 'session1'),
        throwsA(isA<Exception>()),
      );
    });

    test('renameFile preserves version history', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/file.txt', content1, sessionId: 'session1');
      await storage.writeFile('/file.txt', content2, sessionId: 'session1');

      await storage.renameFile('/file.txt', '/renamed.txt', sessionId: 'session1');

      // Check history of original file
      final oldHistory = await storage.getFileHistory('/file.txt', sessionId: 'session1');
      expect(oldHistory.length, equals(2));

      // Check renamed file has new version
      final renamedFile = await storage.readFile('/renamed.txt', sessionId: 'session1');
      expect(renamedFile, isNotNull);
      expect(renamedFile!.version, equals(1)); // New file starts at version 1
      expect(utf8.decode(renamedFile.content), equals('Version 2'));
    });

    test('getSessionFiles returns all files in session', () async {
      await storage.writeFile('/dir1/file1.txt', utf8.encode('Content 1'), sessionId: 'session1');
      await storage.writeFile('/dir1/file2.txt', utf8.encode('Content 2'), sessionId: 'session1');
      await storage.writeFile('/dir2/file3.txt', utf8.encode('Content 3'), sessionId: 'session1');
      await storage.writeFile('/other.txt', utf8.encode('Other'), sessionId: 'session2');

      final files = await storage.getSessionFiles('session1');

      expect(files.length, equals(3));
      expect(files.any((f) => f.path == '/dir1/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir1/file2.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir2/file3.txt'), isTrue);
      expect(files.any((f) => f.path == '/other.txt'), isFalse);
    });

    test('getAllSessions returns all session IDs', () async {
      await storage.writeFile('/file1.txt', utf8.encode('Content 1'), sessionId: 'session1');
      await storage.writeFile('/file2.txt', utf8.encode('Content 2'), sessionId: 'session2');
      await storage.writeFile('/file3.txt', utf8.encode('Content 3'), sessionId: 'session3');

      final sessions = await storage.getAllSessions();

      expect(sessions.length, equals(3));
      expect(sessions.contains('session1'), isTrue);
      expect(sessions.contains('session2'), isTrue);
      expect(sessions.contains('session3'), isTrue);
    });

    test('multiple operations maintain data integrity', () async {
      // Write multiple files
      await storage.writeFile('/dir1/file1.txt', utf8.encode('Content 1'), sessionId: 'session1');
      await storage.writeFile('/dir1/file2.txt', utf8.encode('Content 2'), sessionId: 'session1');
      await storage.writeFile('/dir2/file3.txt', utf8.encode('Content 3'), sessionId: 'session1');

      // Move a file
      await storage.moveFile('/dir1/file1.txt', '/dir2/file1.txt', sessionId: 'session1');

      // Rename a file
      await storage.renameFile('/dir2/file3.txt', '/dir2/file3_renamed.txt', sessionId: 'session1');

      // Verify final state
      final dir1Files = await storage.listDirectory('/dir1', sessionId: 'session1');
      final dir2Files = await storage.listDirectory('/dir2', sessionId: 'session1');

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
        storage.writeFile('/concurrent.txt', content1, sessionId: 'session1'),
        Future.delayed(Duration(milliseconds: 10), () => storage.writeFile('/concurrent.txt', content2, sessionId: 'session1')),
        Future.delayed(Duration(milliseconds: 20), () => storage.writeFile('/concurrent.txt', content3, sessionId: 'session1')),
      ]);

      final history = await storage.getFileHistory('/concurrent.txt', sessionId: 'session1');
      expect(history.length, equals(3));
    });

    test('file paths are case sensitive', () async {
      await storage.writeFile('/File.txt', utf8.encode('Upper'), sessionId: 'session1');
      await storage.writeFile('/file.txt', utf8.encode('Lower'), sessionId: 'session1');

      final upper = await storage.readFile('/File.txt', sessionId: 'session1');
      final lower = await storage.readFile('/file.txt', sessionId: 'session1');

      expect(upper, isNotNull);
      expect(lower, isNotNull);
      expect(utf8.decode(upper!.content), equals('Upper'));
      expect(utf8.decode(lower!.content), equals('Lower'));
    });

    test('empty file content is handled correctly', () async {
      final id = await storage.writeFile('/empty.txt', [], sessionId: 'session1');

      expect(id, isNotNull);
      final record = await storage.readFile('/empty.txt', sessionId: 'session1');
      expect(record, isNotNull);
      expect(record!.content, isEmpty);
    });

    test('binary content is stored correctly', () async {
      final binaryContent = List.generate(256, (i) => i);
      final id = await storage.writeFile('/binary.bin', binaryContent, sessionId: 'session1');

      expect(id, isNotNull);
      final record = await storage.readFile('/binary.bin', sessionId: 'session1');
      expect(record, isNotNull);
      expect(record!.content, equals(binaryContent));
    });
  });

  group('MCP Tool Integration Tests', () {
    test('write_file tool functionality', () async {
      final content = utf8.encode('Test content');
      final id = await storage.writeFile('/test.txt', content, sessionId: 'session1');

      expect(id, isNotNull);
      expect(id.length, greaterThan(0));
    });

    test('read_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test.txt', content, sessionId: 'session1');

      final record = await storage.readFile('/test.txt', sessionId: 'session1');

      expect(record, isNotNull);
      expect(record!.path, equals('/test.txt'));
      expect(utf8.decode(record.content), equals('Test content'));
    });

    test('list_directory tool functionality', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/dir/file.txt', content, sessionId: 'session1');

      final files = await storage.listDirectory('/dir', sessionId: 'session1');

      expect(files, isNotEmpty);
      expect(files.first.path, equals('/dir/file.txt'));
    });

    test('move_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/source.txt', content, sessionId: 'session1');

      final newId = await storage.moveFile('/source.txt', '/dest.txt', sessionId: 'session1');

      expect(newId, isNotNull);
      final moved = await storage.readFile('/dest.txt', sessionId: 'session1');
      expect(moved, isNotNull);
      expect(utf8.decode(moved!.content), equals('Test content'));
    });

    test('rename_file tool functionality', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/old.txt', content, sessionId: 'session1');

      final newId = await storage.renameFile('/old.txt', '/new.txt', sessionId: 'session1');

      expect(newId, isNotNull);
      final renamed = await storage.readFile('/new.txt', sessionId: 'session1');
      expect(renamed, isNotNull);
      expect(utf8.decode(renamed!.content), equals('Test content'));
    });

    test('getSessionFiles returns latest versions only', () async {
      await storage.writeFile('/file.txt', utf8.encode('Version 1'), sessionId: 'session1');
      await storage.writeFile('/file.txt', utf8.encode('Version 2'), sessionId: 'session1');
      await storage.writeFile('/file.txt', utf8.encode('Version 3'), sessionId: 'session1');

      final files = await storage.getSessionFiles('session1');

      expect(files.length, equals(1));
      expect(files.first.version, equals(3));
      expect(utf8.decode(files.first.content), equals('Version 3'));
    });
  });
}
