// Copyright (c) 2025, ThreadBox MCP contributors.

/// ThreadBox MCP Server providing file system tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as path;
import 'storage.dart';

/// Main MCP server for ThreadBox providing file operations.
base class ThreadBoxServer extends MCPServer with ToolsSupport {
  final FileStorage _storage;
  final String _dataPath;

  ThreadBoxServer(super.channel, this._storage, this._dataPath)
    : super.fromStreamChannel(
        implementation: Implementation(
          name: 'ThreadBox MCP Server',
          version: '0.1.0',
        ),
        instructions: 'Virtual filesystem for AI agent artifacts with versioned storage',
      ) {
    // Register MCP tools
    registerTool(writeFileTool, _writeFile);
    registerTool(readFileTool, _readFile);
    registerTool(listDirectoryTool, _listDirectory);
    registerTool(exportSessionZipTool, _exportSessionZip);
    registerTool(moveFileTool, _moveFile);
    registerTool(renameFileTool, _renameFile);
  }

  /// Tool for writing files to storage.
  final writeFileTool = Tool(
    name: 'write_file',
    description: 'Write a file to the virtual filesystem with automatic versioning',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
        'path': Schema.string(
          description: 'The file path relative to the session',
        ),
        'content': Schema.string(
          description: 'The file content (text or base64 encoded for binary)',
        ),
        'base64': Schema.boolean(
          description: 'Whether content is base64 encoded (default: false)',
        ),
      },
      required: ['sessionId', 'path', 'content'],
    ),
  );

  /// Tool for reading files from storage.
  final readFileTool = Tool(
    name: 'read_file',
    description: 'Read the latest version of a file from the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
        'path': Schema.string(
          description: 'The file path relative to the session',
        ),
      },
      required: ['sessionId', 'path'],
    ),
  );

  /// Tool for listing directory contents.
  final listDirectoryTool = Tool(
    name: 'list_directory',
    description: 'List all files and directories in a directory from the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
        'path': Schema.string(
          description: 'The directory path relative to the session',
        ),
      },
      required: ['sessionId', 'path'],
    ),
  );

  /// Tool for exporting session as ZIP archive.
  final exportSessionZipTool = Tool(
    name: 'export_session_zip',
    description: 'Export all files in a session as a ZIP archive',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
      },
      required: ['sessionId'],
    ),
  );

  /// Tool for moving files from one path to another.
  final moveFileTool = Tool(
    name: 'move_file',
    description: 'Move a file from one path to another in the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
        'from_path': Schema.string(
          description: 'The source file path',
        ),
        'to_path': Schema.string(
          description: 'The destination file path',
        ),
      },
      required: ['sessionId', 'from_path', 'to_path'],
    ),
  );

  /// Tool for renaming files.
  final renameFileTool = Tool(
    name: 'rename_file',
    description: 'Rename a file in the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'sessionId': Schema.string(
          description: 'Session ID (typically Git branch/worktree name)',
        ),
        'old_path': Schema.string(
          description: 'The current file path',
        ),
        'new_path': Schema.string(
          description: 'The new file path',
        ),
      },
      required: ['sessionId', 'old_path', 'new_path'],
    ),
  );

  /// Implementation of write_file tool.
  FutureOr<CallToolResult> _writeFile(CallToolRequest request) async {
    final sessionId = request.arguments!['sessionId'] as String;
    final filePath = request.arguments!['path'] as String;
    final contentStr = request.arguments!['content'] as String;
    final isBase64 = request.arguments!['base64'] as bool? ?? false;

    try {
      final List<int> contentBytes;
      if (isBase64) {
        contentBytes = base64Decode(contentStr);
      } else {
        contentBytes = utf8.encode(contentStr);
      }

      final inodeId = await _storage.writeFile(filePath, contentBytes, sessionId: sessionId);
      final record = await _storage.readFile(filePath, sessionId: sessionId);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'inodeId': inodeId,
              'version': record!.version,
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
    final sessionId = request.arguments!['sessionId'] as String;
    final filePath = request.arguments!['path'] as String;

    try {
      final record = await _storage.readFile(filePath, sessionId: sessionId);

      if (record == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'File not found: $filePath',
            ),
          ],
          isError: true,
        );
      }

      // Try to decode as UTF-8, fallback to base64 if not valid
      String contentStr;
      bool isBase64 = false;
      try {
        contentStr = utf8.decode(record.content);
        // Check if it's actually valid text (not binary)
        if (record.content.any((b) => b < 32 && b != 9 && b != 10 && b != 13)) {
          // Contains non-printable characters, encode as base64
          contentStr = base64Encode(record.content);
          isBase64 = true;
        }
      } catch (_) {
        // Not valid UTF-8, encode as base64
        contentStr = base64Encode(record.content);
        isBase64 = true;
      }

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'content': contentStr,
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
    final sessionId = request.arguments!['sessionId'] as String;
    final dirPath = request.arguments!['path'] as String;

    try {
      final files = await _storage.listDirectory(dirPath, sessionId: sessionId);

      // Build directory structure
      final Set<String> directories = {};
      final List<String> fileList = [];

      for (final file in files) {
        // Remove the directory prefix
        final relativePath = file.path.startsWith(dirPath)
            ? file.path.substring(dirPath.length)
            : file.path;
        
        // Remove leading slash
        final cleanPath = relativePath.startsWith('/')
            ? relativePath.substring(1)
            : relativePath;

        if (cleanPath.isEmpty) continue;

        // Check if this is a direct child or nested
        final parts = cleanPath.split('/');
        if (parts.length == 1) {
          // Direct file
          fileList.add(cleanPath);
        } else {
          // Nested - add first directory
          directories.add(parts[0]);
        }
      }

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'directories': directories.toList()..sort(),
              'files': fileList..sort(),
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
    final sessionId = request.arguments!['sessionId'] as String;

    try {
      final files = await _storage.getSessionFiles(sessionId);

      if (files.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No files found in session: $sessionId',
            ),
          ],
          isError: true,
        );
      }

      // Create ZIP archive
      final archive = Archive();
      for (final file in files) {
        // Remove leading slash from path for ZIP
        final zipPath = file.path.startsWith('/')
            ? file.path.substring(1)
            : file.path;
        
        archive.addFile(ArchiveFile(
          zipPath,
          file.content.length,
          file.content,
        ));
      }

      // Encode ZIP
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      // Save to file
      final timestamp = DateTime.now().toIso8601String().split('T')[0];
      final zipFileName = 'threadbox-session-$sessionId-$timestamp.zip';
      final zipPath = path.join(_dataPath, zipFileName);
      
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData!);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'downloadPath': zipPath,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error exporting session ZIP: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of move_file tool.
  FutureOr<CallToolResult> _moveFile(CallToolRequest request) async {
    final sessionId = request.arguments!['sessionId'] as String;
    final fromPath = request.arguments!['from_path'] as String;
    final toPath = request.arguments!['to_path'] as String;

    try {
      final inodeId = await _storage.moveFile(fromPath, toPath, sessionId: sessionId);
      final record = await _storage.readFile(toPath, sessionId: sessionId);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'inodeId': inodeId,
              'version': record!.version,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error moving file: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of rename_file tool.
  FutureOr<CallToolResult> _renameFile(CallToolRequest request) async {
    final sessionId = request.arguments!['sessionId'] as String;
    final oldPath = request.arguments!['old_path'] as String;
    final newPath = request.arguments!['new_path'] as String;

    try {
      final inodeId = await _storage.renameFile(oldPath, newPath, sessionId: sessionId);
      final record = await _storage.readFile(newPath, sessionId: sessionId);

      return CallToolResult(
        content: [
          TextContent(
            text: jsonEncode({
              'inodeId': inodeId,
              'version': record!.version,
            }),
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error renaming file: $e',
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
