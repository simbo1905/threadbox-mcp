// Copyright (c) 2025, ThreadBox MCP contributors.

/// ThreadBox MCP Server providing file system tools.
library;

import 'dart:async';
import 'dart:convert';

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
    registerTool(createFileTool, _createFile);
    registerTool(readFileTool, _readFile);
    registerTool(listDirectoryTool, _listDirectory);
    registerTool(renameNodeTool, _renameNode);
    registerTool(moveNodeTool, _moveNode);
  }

  final FileStorage _storage;

  /// Tool for writing files to storage.
  final createFileTool = Tool(
    name: 'create_file',
    description: 'Create a file in the virtual filesystem.',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'Absolute path of the file to create.',
        ),
        'content': Schema.string(
          description: 'File contents. Defaults to utf8 unless encoding=base64.',
        ),
        'encoding': Schema.string(
          description: 'Content encoding (utf8 or base64). Defaults to utf8.',
        ),
        'worktree': Schema.string(
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
        'worktree': Schema.string(
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
        'worktree': Schema.string(
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
        'worktree': Schema.string(
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
        'worktree': Schema.string(
          description: 'Optional isolation key for multi-worktree storage.',
        ),
      },
      required: ['path', 'newDirectory'],
    ),
  );

  Future<CallToolResult> _createFile(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final content = args['content'] as String;
    final encoding = (args['encoding'] as String?)?.toLowerCase() ?? 'utf8';
    final worktree = args['worktree'] as String?;

    try {
      final bytes = encoding == 'base64'
          ? base64Decode(content)
          : utf8.encode(content);
      final entry = await _storage.createFile(
        path,
        bytes,
        worktree: worktree,
      );
      return _success(entry.toJson());
    } on FormatException catch (e) {
      return _error('Failed to decode content for $path: ${e.message}');
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error creating $path: $e');
    }
  }

  Future<CallToolResult> _readFile(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final worktree = args['worktree'] as String?;

    try {
      final record = await _storage.readFile(path, worktree: worktree);
      if (record == null) {
        return _error('File not found: $path');
      }
      return _success(record.toJson(includeContent: true));
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error reading $path: $e');
    }
  }

  Future<CallToolResult> _listDirectory(CallToolRequest request) async {
    final args = request.arguments!;
    final path = args['path'] as String;
    final worktree = args['worktree'] as String?;

    try {
      final entries = await _storage.listDirectory(path, worktree: worktree);
      final payload = {
        'path': path,
        'entries': [for (final entry in entries) entry.toJson()],
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
    final worktree = args['worktree'] as String?;

    try {
      final entry = await _storage.renameNode(
        path,
        newName,
        worktree: worktree,
      );
      return _success(entry.toJson());
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
    final worktree = args['worktree'] as String?;

    try {
      final entry = await _storage.moveNode(
        path,
        newDirectory,
        worktree: worktree,
      );
      return _success(entry.toJson());
    } on StorageException catch (e) {
      return _error(e.message);
    } catch (e) {
      return _error('Unexpected error moving $path: $e');
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
