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

  tearDown(() {
    // Clean up
    storage.close();
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

    test('listDirectory returns files in directory', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content);
      await storage.writeFile('/dir/file2.txt', content);
      await storage.writeFile('/other/file3.txt', content);

      final files = await storage.listDirectory('/dir');

      expect(files.length, equals(2));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/file2.txt'), isTrue);
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

    test('UUID primary key is unique for each write', () async {
      final content = utf8.encode('Same content');

      final id1 = await storage.writeFile('/test/file.txt', content);
      final id2 = await storage.writeFile('/test/file.txt', content);

      expect(id1, isNot(equals(id2)));
    });
  });

  group('MCP Tool Endpoints (Placeholder)', () {
    test('write_file tool functionality', () async {
      // Placeholder test for write_file MCP tool
      final content = utf8.encode('Test content');
      final id = await storage.writeFile('/test.txt', content);

      expect(id, isNotNull);
      expect(id.length, greaterThan(0));
    });

    test('read_file tool functionality', () async {
      // Placeholder test for read_file MCP tool
      final content = utf8.encode('Test content');
      await storage.writeFile('/test.txt', content);

      final record = await storage.readFile('/test.txt');

      expect(record, isNotNull);
      expect(record!.path, equals('/test.txt'));
    });

    test('list_directory tool functionality', () async {
      // Placeholder test for list_directory MCP tool
      final content = utf8.encode('Test');
      await storage.writeFile('/dir/file.txt', content);

      final files = await storage.listDirectory('/dir');

      expect(files, isNotEmpty);
    });

    test('export_zip tool placeholder', () {
      // Placeholder test for export_zip MCP tool
      // Will be implemented with actual ZIP functionality
      expect(true, isTrue);
    });
  });
}
