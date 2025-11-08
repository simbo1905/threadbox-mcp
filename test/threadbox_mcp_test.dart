// Copyright (c) 2025, ThreadBox MCP contributors.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_mcp/api.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

void main() {
  group('FileStorage', () {
    late FileStorage storage;
    late String tempDbPath;

    setUp(() async {
      tempDbPath =
          '${Directory.systemTemp.path}/threadbox_test_${DateTime.now().microsecondsSinceEpoch}.db';
      storage = await FileStorage.open(tempDbPath);
    });

    tearDown(() async {
      await storage.close();
      final dbFile = File(tempDbPath);
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
    });

    test('writeFile creates new versions when overwriting', () async {
      final entry1 = await storage.writeFile(
        '/docs/readme.md',
        utf8.encode('Version 1'),
      );
      expect(entry1.version, equals(1));

      final entry2 = await storage.writeFile(
        '/docs/readme.md',
        utf8.encode('Version 2'),
      );
      expect(entry2.version, equals(2));

      final history = await storage.getFileHistory('/docs/readme.md');
      expect(history, hasLength(2));
      expect(history.first.version, equals(2));
      expect(history.last.version, equals(1));
    });

    test('listDirectory returns directories and files separately', () async {
      await storage.writeFile('/dir/a.txt', utf8.encode('A'));
      await storage.writeFile('/dir/nested/b.txt', utf8.encode('B'));

      final rootListing = await storage.listDirectory('/');
      expect(
        rootListing.directories.map((entry) => entry.name).toList(),
        contains('dir'),
      );

      final dirListing = await storage.listDirectory('/dir');
      expect(dirListing.files.single.name, equals('a.txt'));
      expect(dirListing.directories.single.name, equals('nested'));
    });

    test('renameNode updates metadata without losing history', () async {
      await storage.writeFile('/plan.txt', utf8.encode('alpha'));
      await storage.writeFile('/plan.txt', utf8.encode('beta'));

      final renamed = await storage.renameNode('/plan.txt', 'plan-renamed.txt');
      expect(renamed.path, equals('/plan-renamed.txt'));
      expect(renamed.version, equals(2));

      expect(await storage.readFile('/plan.txt'), isNull);
      final newRecord = await storage.readFile('/plan-renamed.txt');
      expect(newRecord, isNotNull);
      expect(utf8.decode(newRecord!.content!), equals('beta'));
    });

    test('moveNode relocates file into existing directory', () async {
      await storage.writeFile('/drafts/idea.md', utf8.encode('draft'));
      final moved = await storage.moveNode('/drafts/idea.md', '/archive');

      expect(moved.path, equals('/archive/idea.md'));
      expect(await storage.readFile('/drafts/idea.md'), isNull);
      final relocated = await storage.readFile('/archive/idea.md');
      expect(relocated, isNotNull);
    });

    test('session isolation keeps versions separate', () async {
      await storage.writeFile(
        '/shared.txt',
        utf8.encode('Alpha'),
        sessionId: 'alpha',
      );
      await storage.writeFile(
        '/shared.txt',
        utf8.encode('Beta'),
        sessionId: 'beta',
      );

      final alpha = await storage.readFile('/shared.txt', sessionId: 'alpha');
      final beta = await storage.readFile('/shared.txt', sessionId: 'beta');

      expect(alpha, isNotNull);
      expect(beta, isNotNull);
      expect(utf8.decode(alpha!.content!), equals('Alpha'));
      expect(utf8.decode(beta!.content!), equals('Beta'));
    });

    test('exportSessionZip creates archive with file contents', () async {
      await storage.writeFile(
        '/docs/readme.md',
        utf8.encode('export me'),
        sessionId: 'session-1',
      );

      final zipPath = await storage.exportSessionZip('session-1');
      final file = File(zipPath);
      addTearDown(() {
        if (file.existsSync()) {
          file.deleteSync();
        }
      });

      expect(file.existsSync(), isTrue);

      final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
      final archiveFile = archive.files.singleWhere(
        (f) => f.name == 'docs/readme.md',
      );
      expect(utf8.decode(archiveFile.content), equals('export me'));
    });

    test('renameNode throws when destination exists', () async {
      await storage.writeFile('/a.txt', utf8.encode('A'));
      await storage.writeFile('/b.txt', utf8.encode('B'));

      await expectLater(
        () => storage.renameNode('/a.txt', 'b.txt'),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('ThreadBoxServer tools', () {
    late FileStorage storage;
    late ThreadBoxServer server;
    late StreamChannelController<Object?> controller;
    late String tempDbPath;

    setUp(() async {
      tempDbPath =
          '${Directory.systemTemp.path}/threadbox_server_${DateTime.now().microsecondsSinceEpoch}.db';
      storage = await FileStorage.open(tempDbPath);
      controller = StreamChannelController<Object?>(sync: true);
      server = ThreadBoxServer(controller.foreign, storage);
    });

    tearDown(() async {
      await server.dispose();
      await controller.local.sink.close();
      await controller.foreign.sink.close();
      final dbFile = File(tempDbPath);
      if (dbFile.existsSync()) {
        dbFile.deleteSync();
      }
    });

    test('write_file returns inode and version', () async {
      final result = await server.handleToolForTest(
        'write_file',
        {
          'path': '/notes.txt',
          'content': 'hello world',
          'sessionId': 'main',
        },
      );

      final payload = _decodeSuccess(result);
      expect(payload['inodeId'], isNotEmpty);
      expect(payload['version'], equals(1));
      expect(payload['sessionId'], equals('main'));
    });

    test('write_file accepts base64 content', () async {
      final base64Content = base64Encode(utf8.encode('from base64'));
      final result = await server.handleToolForTest(
        'write_file',
        {
          'path': '/encoded.bin',
          'content': base64Content,
          'base64': true,
          'sessionId': 'main',
        },
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], equals('/encoded.bin'));
      expect(payload['version'], equals(1));
    });

    test('read_file returns utf8 content when possible', () async {
      await storage.writeFile(
        '/readme.txt',
        utf8.encode('content!'),
        sessionId: 'main',
      );

      final result = await server.handleToolForTest(
        'read_file',
        {'path': '/readme.txt', 'sessionId': 'main'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['content'], equals('content!'));
      expect(payload['base64'], isFalse);
    });

    test('list_directory returns directories and files metadata', () async {
      await storage.writeFile('/docs/a.txt', utf8.encode('A'));
      await storage.writeFile('/docs/b/b.txt', utf8.encode('B'));

      final result = await server.handleToolForTest(
        'list_directory',
        {'path': '/docs'},
      );

      final payload = _decodeSuccess(result);
      final directories = (payload['directories'] as List).cast<Map>();
      final files = (payload['files'] as List).cast<Map>();

      expect(files.map((entry) => entry['name']), contains('a.txt'));
      expect(directories.map((entry) => entry['name']), contains('b'));
    });

    test('rename_node updates file path', () async {
      await storage.writeFile('/plan.txt', utf8.encode('secret'));

      final result = await server.handleToolForTest(
        'rename_node',
        {'path': '/plan.txt', 'newName': 'manifest.txt'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], equals('/manifest.txt'));
      expect(await storage.readFile('/plan.txt'), isNull);
    });

    test('move_node relocates file', () async {
      await storage.writeFile('/draft.txt', utf8.encode('draft'));

      final result = await server.handleToolForTest(
        'move_node',
        {'path': '/draft.txt', 'newDirectory': '/projects'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], equals('/projects/draft.txt'));
      expect(await storage.readFile('/projects/draft.txt'), isNotNull);
    });

    test('export_session_zip returns path to archive', () async {
      await storage.writeFile('/docs/readme.md', utf8.encode('zip me'));

      final result = await server.handleToolForTest(
        'export_session_zip',
        {'sessionId': 'main'},
      );

      final payload = _decodeSuccess(result);
      final path = payload['downloadPath'] as String;
      expect(File(path).existsSync(), isTrue);

      addTearDown(() {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
        }
      });
    });

    test('tools surface storage errors', () async {
      final result = await server.handleToolForTest(
        'read_file',
        {'path': '/missing.txt'},
      );

      expect(result.isError, isTrue);
      final message = (result.content.single as TextContent).text;
      expect(message, contains('File not found'));
    });
  });
}

Map<String, dynamic> _decodeSuccess(CallToolResult result) {
  expect(result.isError ?? false, isFalse);
  expect(result.content.single, isA<TextContent>());
  final payload = (result.content.single as TextContent).text;
  return jsonDecode(payload) as Map<String, dynamic>;
}
