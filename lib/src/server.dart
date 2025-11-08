// Copyright (c) 2025, ThreadBox MCP contributors.

/// ThreadBox MCP Server providing file system tools.
library;

import 'dart:async';
import 'dart:convert';
import 'package:dart_mcp/server.dart';
import 'storage.dart';
import 'git_utils.dart';

/// Main MCP server for ThreadBox providing file operations.
base class ThreadBoxServer extends MCPServer with ToolsSupport {
  final FileStorage _storage;
  final String _defaultSessionId;

  ThreadBoxServer(super.channel, this._storage, {String? defaultSessionId})
    : _defaultSessionId = defaultSessionId ?? getSessionId(),
      super.fromStreamChannel(
        implementation: Implementation(
          name: 'ThreadBox MCP Server',
          version: '0.1.0',
        ),
        instructions: 'Virtual filesystem for AI agent artifacts with versioned storage',
      ) {
    // Register MCP tools for file operations
    registerTool(writeFileTool, _writeFile);
    registerTool(readFileTool, _readFile);
    registerTool(listDirectoryTool, _listDirectory);
    registerTool(exportSessionZipTool, _exportSessionZip);
  }

  /// Tool for writing files to storage.
  final writeFileTool = Tool(
    name: 'write_file',
    description: 'Write a file to the virtual filesystem with automatic versioning',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID for isolation (optional, auto-detected from Git worktree)',
        ),
        'path': Schema.string(
          description: 'The file path relative to the session root',
        ),
        'content': Schema.string(
          description: 'The file content (text or base64 encoded for binary)',
        ),
        'base64': Schema.bool(
          description: 'Whether content is base64 encoded (default: false)',
        ),
      },
      required: ['path', 'content'],
    ),
  );

  /// Tool for reading files from storage.
  final readFileTool = Tool(
    name: 'read_file',
    description: 'Read the latest version of a file from the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID for isolation (optional, auto-detected from Git worktree)',
        ),
        'path': Schema.string(
          description: 'The file path relative to the session root',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for listing directory contents.
  final listDirectoryTool = Tool(
    name: 'list_directory',
    description: 'List all files in a directory from the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID for isolation (optional, auto-detected from Git worktree)',
        ),
        'path': Schema.string(
          description: 'The directory path relative to the session root',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for exporting session as ZIP.
  final exportSessionZipTool = Tool(
    name: 'export_session_zip',
    description: 'Export all files from a session as a ZIP archive',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID to export (optional, auto-detected from Git worktree)',
        ),
      },
      required: [],
    ),
  );

  /// Implementation of write_file tool.
  FutureOr<CallToolResult> _writeFile(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final content = request.arguments!['content'] as String;
    final sessionId = request.arguments!['sessionId'] as String? ?? _defaultSessionId;
    final base64 = request.arguments!['base64'] as bool? ?? false;

    try {
      final contentBytes = base64 
          ? base64Decode(content)
          : utf8.encode(content);
      
      final id = await _storage.writeFile(path, contentBytes, sessionId: sessionId);

      // Get version
      final record = await _storage.readFile(path, sessionId: sessionId);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'inodeId': id,
              'version': record?.version ?? 1,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error writing file: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of read_file tool.
  FutureOr<CallToolResult> _readFile(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final sessionId = request.arguments!['sessionId'] as String? ?? _defaultSessionId;

    try {
      final record = await _storage.readFile(path, sessionId: sessionId);

      if (record == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'File not found: $path',
            ),
          ],
          isError: true,
        );
      }

      // Try to decode as UTF-8, fallback to base64 for binary
      String content;
      bool isBase64 = false;
      
      try {
        content = utf8.decode(record.content);
      } catch (e) {
        content = base64Encode(record.content);
        isBase64 = true;
      }

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'content': content,
              'base64': isBase64,
              'version': record.version,
              'inodeId': record.id,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error reading file: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of list_directory tool.
  FutureOr<CallToolResult> _listDirectory(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final sessionId = request.arguments!['sessionId'] as String? ?? _defaultSessionId;

    try {
      final files = await _storage.listDirectory(path, sessionId: sessionId);

      final directories = <String>[];
      final filesList = <String>[];

      for (final file in files) {
        // Extract just the filename/dirname
        final relativePath = file.path.substring(path.length);
        final cleanPath = relativePath.startsWith('/') 
            ? relativePath.substring(1) 
            : relativePath;
        
        if (file.isDirectory) {
          // Remove trailing slash for directory names
          final dirName = cleanPath.endsWith('/') 
              ? cleanPath.substring(0, cleanPath.length - 1)
              : cleanPath;
          directories.add(dirName);
        } else {
          filesList.add(cleanPath);
        }
      }

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'directories': directories,
              'files': filesList,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error listing directory: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of export_session_zip tool.
  FutureOr<CallToolResult> _exportSessionZip(CallToolRequest request) async {
    final sessionId = request.arguments?['sessionId'] as String? ?? _defaultSessionId;

    try {
      final downloadPath = await _storage.exportSessionZip(sessionId);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'downloadPath': downloadPath,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error exporting session: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  Future<void> dispose() async {
    await _storage.close();
  }
}
