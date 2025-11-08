// Copyright (c) 2025, ThreadBox MCP contributors.

/// ThreadBox MCP Server providing file system tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_mcp/server.dart';
import 'package:meta/meta.dart';

import 'storage.dart';

/// Main MCP server for ThreadBox providing file operations.
base class ThreadBoxServer extends MCPServer with ToolsSupport {
  ThreadBoxServer(super.channel, this._storage)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'ThreadBox MCP Server',
          version: '0.2.0',
        ),
        instructions: 'Virtual filesystem backed by sqlite_async storage.',
      ) {
    registerTool(writeFileTool, _writeFile);
    registerTool(readFileTool, _readFile);
    registerTool(listDirectoryTool, _listDirectory);
    registerTool(renameNodeTool, _renameNode);
    registerTool(moveNodeTool, _moveNode);
    registerTool(exportSessionZipTool, _exportSessionZip);
  }

  final FileStorage _storage;

  /// Tool for writing files to storage.
  final writeFileTool = Tool(
    name: 'write_file',
    description: 'Create or update a file in the virtual filesystem.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Absolute path of the file to create.',
        ),
        'content': Schema.string(
          description: 'File contents. UTF-8 by default unless base64=true.',
        ),
        'base64': Schema.boolean(
          description: 'Set to true when content is base64 encoded.',
        ),
        'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path', 'content'],
    ),
  );

  /// Tool for reading files from storage.
  final readFileTool = Tool(
    name: 'read_file',
    description: 'Read a file from the virtual filesystem.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Absolute path of the file to read.',
        ),
          'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for listing directory contents.
  final listDirectoryTool = Tool(
    name: 'list_directory',
    description: 'List the direct children of a directory.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Directory path to list.',
        ),
          'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for renaming a node.
  final renameNodeTool = Tool(
    name: 'rename_node',
    description: 'Rename a file while staying in the same directory.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Existing file path.',
        ),
        'newName': Schema.string(
          description: 'New file name (no path segments).',
        ),
        'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path', 'newName'],
    ),
  );

  /// Tool for moving a node to a different directory.
  final moveNodeTool = Tool(
    name: 'move_node',
    description: 'Move a file to a different directory.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Existing file path.',
        ),
        'newDirectory': Schema.string(
          description: 'Target directory path.',
        ),
        'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path', 'newDirectory'],
    ),
  );

  /// Tool for exporting a session as a ZIP archive.
  final exportSessionZipTool = Tool(
    name: 'export_session_zip',
    description: 'Create a ZIP archive containing all files in a session.',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
        'destination': Schema.string(
          description: 'Optional filesystem directory to place the archive.',
        ),
      },
    ),
  );

  Future<CallToolResult> _writeFile(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final content = args['content'] as String;
    final isBase64 = args['base64'] as bool? ?? false;
    final sessionId = args['sessionId'] as String?;

    try {
      final bytes = isBase64
          ? base64Decode(content)
          : utf8.encode(content);
      final entry = await _storage.writeFile(
        path,
        bytes,
        sessionId: sessionId,
      );
      return _success({
        'inodeId': entry.id,
        'path': entry.path,
        'version': entry.version,
        'sessionId': sessionId,
      });
    } on FormatException catch (e) {
      return _error('Failed to decode content for $path: ${e.message}');
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error writing $path: $e');
    }
  }

  Future<CallToolResult> _readFile(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final sessionId = args['sessionId'] as String?;

    try {
      final record = await _storage.readFile(path, sessionId: sessionId);
      if (record == null) {
        return _error('File not found: $path');
      }
      final bytes = record.content ?? Uint8List(0);
      try {
        final decoded = utf8.decode(bytes);
        return _success({
          'inodeId': record.id,
          'path': record.path,
          'version': record.version,
          'content': decoded,
          'base64': false,
          'sessionId': sessionId,
        });
      } on FormatException {
        return _success({
          'inodeId': record.id,
          'path': record.path,
          'version': record.version,
          'content': base64Encode(bytes),
          'base64': true,
          'sessionId': sessionId,
        });
      }
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error reading $path: $e');
    }
  }

  Future<CallToolResult> _listDirectory(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final sessionId = args['sessionId'] as String?;

    try {
      final listing = await _storage.listDirectory(path, sessionId: sessionId);
      final payload = {
        'sessionId': sessionId,
        'path': path,
        'directories': [
          for (final entry in listing.directories)
            {
              'name': entry.name,
              'path': entry.path,
              'inodeId': entry.id,
              'updatedAt': entry.updatedAt.toIso8601String(),
            }
        ],
        'files': [
          for (final entry in listing.files)
            {
              'name': entry.name,
              'path': entry.path,
              'inodeId': entry.id,
              'version': entry.version,
              'updatedAt': entry.updatedAt.toIso8601String(),
            }
        ],
      };
      return _success(payload);
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error listing $path: $e');
    }
  }

  Future<CallToolResult> _renameNode(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final newName = args['newName'] as String;
    final sessionId = args['sessionId'] as String?;

    try {
      final entry = await _storage.renameNode(
        path,
        newName,
        sessionId: sessionId,
      );
      return _success({
        'inodeId': entry.id,
        'path': entry.path,
        'version': entry.version,
        'sessionId': sessionId,
      });
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error renaming $path: $e');
    }
  }

  Future<CallToolResult> _moveNode(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final newDirectory = args['newDirectory'] as String;
    final sessionId = args['sessionId'] as String?;

    try {
      final entry = await _storage.moveNode(
        path,
        newDirectory,
        sessionId: sessionId,
      );
      return _success({
        'inodeId': entry.id,
        'path': entry.path,
        'version': entry.version,
        'sessionId': sessionId,
      });
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error moving $path: $e');
    }
  }

  Future<CallToolResult> _exportSessionZip(CallToolRequest request) async {
    final args = request.arguments ?? const <String, Object?>{};
    final sessionId = args['sessionId'] as String?;
    final destination = args['destination'] as String?;

    try {
      final path = await _storage.exportSessionZip(
        sessionId,
        destinationDir: destination,
      );
      return _success({
        'sessionId': sessionId,
        'downloadPath': path,
      });
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error exporting session: $e');
    }
  }

  Future<void> dispose() => _storage.close();

  CallToolResult _success(Object data) => CallToolResult(
    content: [TextContent(text: jsonEncode(data))],
  );

  CallToolResult _error(String message) => CallToolResult(
    isError: true,
    content: [TextContent(text: message)],
  );

  @visibleForTesting
  Future<CallToolResult> handleToolForTest(
    String toolName,
    Map<String, Object?> arguments,
  ) async {
    final impl = _registeredToolImpls[toolName];
    if (impl == null) {
      throw StateError('No tool registered with the name $toolName');
    }
    return impl(CallToolRequest(name: toolName, arguments: arguments));
  }
}
