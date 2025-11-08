// Copyright (c) 2025, ThreadBox MCP contributors.

import 'dart:convert';
import 'dart:io';

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

    test('createFile persists file metadata and content', () async {
      final entry = await storage.createFile(
        '/docs/readme.md',
        utf8.encode('Hello world'),
      );

      expect(entry.path, '/docs/readme.md');
      expect(entry.type, NodeType.file);
      expect(utf8.decode(entry.content!), 'Hello world');

      final reloaded = await storage.readFile('/docs/readme.md');
      expect(reloaded, isNotNull);
      expect(utf8.decode(reloaded!.content!), 'Hello world');
    });

    test('readFile returns null for missing file', () async {
      final result = await storage.readFile('/missing.txt');
      expect(result, isNull);
    });

    test('listDirectory returns direct children', () async {
      await storage.createFile('/dir/a.txt', utf8.encode('A'));
      await storage.createFile('/dir/b.txt', utf8.encode('B'));
      await storage.createFile('/other/c.txt', utf8.encode('C'));

      final entries = await storage.listDirectory('/dir');
      final names = entries.map((e) => e.name).toList();

      expect(names, containsAll(<String>['a.txt', 'b.txt']));
      expect(names, isNot(contains('c.txt')));
    });

    test('renameNode updates the path without affecting content', () async {
      await storage.createFile('/file.txt', utf8.encode('data'));

      final renamed = await storage.renameNode('/file.txt', 'renamed.txt');

      expect(renamed.path, '/renamed.txt');
      expect(utf8.decode(renamed.content!), 'data');
      expect(await storage.readFile('/file.txt'), isNull);
      expect(
        utf8.decode((await storage.readFile('/renamed.txt'))!.content!),
        'data',
      );
    });

    test('moveNode relocates the file and creates directories as needed',
        () async {
      await storage.createFile('/file.txt', utf8.encode('payload'));

      final moved = await storage.moveNode('/file.txt', '/archive');

      expect(moved.path, '/archive/file.txt');
      expect(utf8.decode(moved.content!), 'payload');

      final listing = await storage.listDirectory('/archive');
      expect(listing.map((e) => e.path), contains('/archive/file.txt'));
    });

    test('worktree isolation keeps versions separate', () async {
      await storage.createFile(
        '/shared.txt',
        utf8.encode('Alpha'),
        worktree: 'alpha',
      );
      await storage.createFile(
        '/shared.txt',
        utf8.encode('Beta'),
        worktree: 'beta',
      );

      final alpha = await storage.readFile('/shared.txt', worktree: 'alpha');
      final beta = await storage.readFile('/shared.txt', worktree: 'beta');

      expect(alpha, isNotNull);
      expect(beta, isNotNull);
      expect(utf8.decode(alpha!.content!), 'Alpha');
      expect(utf8.decode(beta!.content!), 'Beta');
    });

    test('renameNode throws when destination already exists', () async {
      await storage.createFile('/a.txt', utf8.encode('A'));
      await storage.createFile('/b.txt', utf8.encode('B'));

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

    test('create_file tool stores UTF8 content', () async {
      final result = await server.handleToolForTest(
        'create_file',
        {'path': '/notes.txt', 'content': 'hello world'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], '/notes.txt');

      final stored = await storage.readFile('/notes.txt');
      expect(stored, isNotNull);
      expect(utf8.decode(stored!.content!), 'hello world');
    });

    test('create_file tool accepts base64 content', () async {
      final base64Content = base64Encode(utf8.encode('from base64'));
      final result = await server.handleToolForTest(
        'create_file',
        {
          'path': '/encoded.bin',
          'content': base64Content,
          'encoding': 'base64',
        },
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], '/encoded.bin');
      final stored = await storage.readFile('/encoded.bin');
      expect(stored, isNotNull);
      expect(utf8.decode(stored!.content!), 'from base64');
    });

    test('read_file tool returns base64 content payload', () async {
      await storage.createFile('/readme.txt', utf8.encode('content!'));

      final result = await server.handleToolForTest(
        'read_file',
        {'path': '/readme.txt'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], '/readme.txt');
      expect(
        utf8.decode(base64Decode(payload['content'] as String)),
        'content!',
      );
    });

    test('list_directory tool returns children metadata', () async {
      await storage.createFile('/docs/a.txt', utf8.encode('a'));
      await storage.createFile('/docs/b.txt', utf8.encode('b'));

      final result = await server.handleToolForTest(
        'list_directory',
        {'path': '/docs'},
      );

      final payload = _decodeSuccess(result);
      final entries = (payload['entries'] as List<dynamic>)
          .cast<Map<String, Object?>>();
      expect(entries.map((e) => e['name']), containsAll(['a.txt', 'b.txt']));
    });

    test('rename_node tool updates filename', () async {
      await storage.createFile('/plan.txt', utf8.encode('secret'));

      final result = await server.handleToolForTest(
        'rename_node',
        {'path': '/plan.txt', 'newName': 'manifest.txt'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], '/manifest.txt');
      expect(await storage.readFile('/plan.txt'), isNull);
    });

    test('move_node tool relocates file', () async {
      await storage.createFile('/draft.txt', utf8.encode('draft'));

      final result = await server.handleToolForTest(
        'move_node',
        {'path': '/draft.txt', 'newDirectory': '/projects'},
      );

      final payload = _decodeSuccess(result);
      expect(payload['path'], '/projects/draft.txt');
      expect(await storage.readFile('/projects/draft.txt'), isNotNull);
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
