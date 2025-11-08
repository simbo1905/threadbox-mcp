// Copyright (c) 2025, ThreadBox MCP contributors.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';
import 'package:archive/archive.dart';

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

  group('Session-based Operations', () {
    test('files in different sessions are isolated', () async {
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

    test('listSessions returns all active sessions', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/file.txt', content, sessionId: 'session-1');
      await storage.writeFile('/file.txt', content, sessionId: 'session-2');
      await storage.writeFile('/file.txt', content, sessionId: 'session-3');

      final sessions = await storage.listSessions();

      expect(sessions.length, equals(3));
      expect(sessions, contains('session-1'));
      expect(sessions, contains('session-2'));
      expect(sessions, contains('session-3'));
    });

    test('listSessions excludes deleted files', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/file.txt', content, sessionId: 'session1');
      await storage.writeFile('/file.txt', content, sessionId: 'session2');
      await storage.deleteFile('/file.txt', sessionId: 'session1');

      final sessions = await storage.listSessions();

      expect(sessions, contains('session2'));
      expect(sessions, isNot(contains('session1')));
    });

    test('operations respect session isolation', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content, sessionId: 'session1');
      await storage.writeFile('/test/file.txt', content, sessionId: 'session2');

      await storage.moveFile('/test/file.txt', '/moved/file.txt', sessionId: 'session1');

      final session1Old = await storage.readFile('/test/file.txt', sessionId: 'session1');
      final session1New = await storage.readFile('/moved/file.txt', sessionId: 'session1');
      final session2File = await storage.readFile('/test/file.txt', sessionId: 'session2');

      expect(session1Old, isNull);
      expect(session1New, isNotNull);
      expect(session2File, isNotNull); // session2 file should be unaffected
    });
  });

  group('Export Session ZIP', () {
    test('exportSessionZip creates valid ZIP file', () async {
      final content1 = utf8.encode('File 1 content');
      final content2 = utf8.encode('File 2 content');
      
      await storage.writeFile('/src/file1.txt', content1, sessionId: 'test-session');
      await storage.writeFile('/src/file2.txt', content2, sessionId: 'test-session');

      final zipPath = await storage.exportSessionZip('test-session', 
          outputDir: Directory.systemTemp.path);

      expect(File(zipPath).existsSync(), isTrue);

      // Verify ZIP contents
      final zipBytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      expect(archive.length, equals(2));
      expect(archive.any((f) => f.name == 'src/file1.txt'), isTrue);
      expect(archive.any((f) => f.name == 'src/file2.txt'), isTrue);

      // Clean up
      File(zipPath).deleteSync();
    });

    test('exportSessionZip includes nested directories', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/a/b/c/file.txt', content, sessionId: 'nested');

      final zipPath = await storage.exportSessionZip('nested', 
          outputDir: Directory.systemTemp.path);

      final zipBytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      expect(archive.any((f) => f.name == 'a/b/c/file.txt'), isTrue);

      File(zipPath).deleteSync();
    });

    test('exportSessionZip throws for empty session', () async {
      expect(
        () => storage.exportSessionZip('non-existent'),
        throwsException,
      );
    });

    test('exportSessionZip preserves file timestamps', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/file.txt', content, sessionId: 'timestamp-test');

      final zipPath = await storage.exportSessionZip('timestamp-test',
          outputDir: Directory.systemTemp.path);

      final zipBytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      final file = archive.firstWhere((f) => f.name == 'file.txt');
      expect(file.lastModTime, greaterThan(0));

      File(zipPath).deleteSync();
    });
  });

  group('Session Dump', () {
    test('dumpSessions returns all session data', () async {
      final content = utf8.encode('Test');
      
      await storage.writeFile('/file1.txt', content, sessionId: 'session1');
      await storage.writeFile('/file2.txt', content, sessionId: 'session2');

      final dump = await storage.dumpSessions();

      expect(dump.keys, contains('session1'));
      expect(dump.keys, contains('session2'));
      expect(dump['session1']['fileCount'], equals(1));
      expect(dump['session2']['fileCount'], equals(1));
    });

    test('dumpSessions includes file details', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test.txt', content, sessionId: 'detailed');

      final dump = await storage.dumpSessions();
      final session = dump['detailed'];
      final files = session['files'] as List;

      expect(files.length, equals(1));
      expect(files[0]['path'], equals('/test.txt'));
      expect(files[0]['isDirectory'], equals(false));
      expect(files[0]['version'], equals(1));
      expect(files[0]['size'], equals(content.length));
    });

    test('dumpSessions returns empty map for no sessions', () async {
      final dump = await storage.dumpSessions();
      expect(dump, isEmpty);
    });
  });

  group('Config Management', () {
    test('defaultDataPath returns valid path', () {
      final dataPath = ThreadBoxConfig.defaultDataPath;
      expect(dataPath, contains('.threadbox'));
      expect(dataPath, contains('data'));
    });

    test('getDatabasePath creates correct path', () {
      final dbPath = ThreadBoxConfig.getDatabasePath('/test/path');
      expect(dbPath, equals('/test/path/threadbox.db'));
    });

    test('ensureDataDirectory creates directory', () async {
      final testDir = '${Directory.systemTemp.path}/threadbox_config_test_${DateTime.now().millisecondsSinceEpoch}';
      
      await ThreadBoxConfig.ensureDataDirectory(testDir);
      
      expect(Directory(testDir).existsSync(), isTrue);
      
      // Clean up
      Directory(testDir).deleteSync(recursive: true);
    });
  });

  group('Git Worktree Detection', () {
    test('getSessionId returns fallback when not in Git', () {
      final sessionId = getSessionId('custom-fallback');
      expect(sessionId, isNotEmpty);
      // Will be either detected worktree or fallback
    });

    test('getSessionId with default fallback', () {
      final sessionId = getSessionId();
      expect(sessionId, isNotEmpty);
    });
  });

  group('Storage Basic Operations (with sessionId)', () {
    test('writeFile stores content with sessionId', () async {
      final content = utf8.encode('Hello, World!');
      final id = await storage.writeFile('/test/file.txt', content, sessionId: 'test-session');

      expect(id, isNotNull);
      expect(id.length, equals(36)); // UUID v4 length
    });

    test('readFile retrieves latest version with sessionId', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');

      await storage.writeFile('/test/file.txt', content1, sessionId: 'versioned');
      await storage.writeFile('/test/file.txt', content2, sessionId: 'versioned');

      final record = await storage.readFile('/test/file.txt', sessionId: 'versioned');

      expect(record, isNotNull);
      expect(record!.version, equals(2));
      expect(utf8.decode(record.content), equals('Version 2'));
    });

    test('listDirectory works with sessionId', () async {
      final content = utf8.encode('Test content');

      await storage.writeFile('/dir/file1.txt', content, sessionId: 'list-test');
      await storage.writeFile('/dir/file2.txt', content, sessionId: 'list-test');
      await storage.writeFile('/other/file3.txt', content, sessionId: 'list-test');

      final files = await storage.listDirectory('/dir', sessionId: 'list-test');

      expect(files.length, equals(2));
      expect(files.any((f) => f.path == '/dir/file1.txt'), isTrue);
      expect(files.any((f) => f.path == '/dir/file2.txt'), isTrue);
    });

    test('deleteFile respects sessionId', () async {
      final content = utf8.encode('Test content');
      await storage.writeFile('/test/file.txt', content, sessionId: 'delete-test');

      await storage.deleteFile('/test/file.txt', sessionId: 'delete-test');

      final file = await storage.readFile('/test/file.txt', sessionId: 'delete-test');
      expect(file, isNull);
    });

    test('exists checks sessionId correctly', () async {
      final content = utf8.encode('Test');
      await storage.writeFile('/test/file.txt', content, sessionId: 'exists-test');

      final exists1 = await storage.exists('/test/file.txt', sessionId: 'exists-test');
      final exists2 = await storage.exists('/test/file.txt', sessionId: 'other-session');

      expect(exists1, isTrue);
      expect(exists2, isFalse);
    });
  });

  group('Complex Scenarios with Sessions', () {
    test('multiple sessions can work concurrently', () async {
      final content = utf8.encode('Test');

      final futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        for (int j = 0; j < 3; j++) {
          futures.add(storage.writeFile('/file$j.txt', content, sessionId: 'session-$i'));
        }
      }

      await Future.wait(futures);

      final sessions = await storage.listSessions();
      expect(sessions.length, equals(5));

      for (int i = 0; i < 5; i++) {
        final files = await storage.listDirectory('/', sessionId: 'session-$i', recursive: true);
        expect(files.length, equals(3));
      }
    });

    test('session export after modifications', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');
      
      await storage.writeFile('/file.txt', content1, sessionId: 'export-test');
      await storage.writeFile('/file.txt', content2, sessionId: 'export-test');

      final zipPath = await storage.exportSessionZip('export-test',
          outputDir: Directory.systemTemp.path);

      // Verify ZIP has latest version
      final zipBytes = File(zipPath).readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final file = archive.firstWhere((f) => f.name == 'file.txt');
      final extracted = utf8.decode(file.content);

      expect(extracted, equals('Version 2'));

      File(zipPath).deleteSync();
    });

    test('getFileHistory works with sessionId', () async {
      final content1 = utf8.encode('Version 1');
      final content2 = utf8.encode('Version 2');
      final content3 = utf8.encode('Version 3');

      await storage.writeFile('/test/file.txt', content1, sessionId: 'history-test');
      await storage.writeFile('/test/file.txt', content2, sessionId: 'history-test');
      await storage.writeFile('/test/file.txt', content3, sessionId: 'history-test');

      final history = await storage.getFileHistory('/test/file.txt', sessionId: 'history-test');

      expect(history.length, equals(3));
      expect(history[0].version, equals(3)); // Most recent first
      expect(history[1].version, equals(2));
      expect(history[2].version, equals(1));
    });
  });
}
