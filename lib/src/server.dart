// Copyright (c) 2025, ThreadBox MCP contributors.

/// ThreadBox MCP Server providing file system tools.
library;

import 'dart:async';
import 'dart:convert';
import 'package:dart_mcp/server.dart';
import 'storage.dart';

/// Main MCP server for ThreadBox providing file operations.
base class ThreadBoxServer extends MCPServer with ToolsSupport {
  final FileStorage _storage;

  ThreadBoxServer(super.channel, this._storage)
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
    registerTool(exportZipTool, _exportZip);
  }

  /// Tool for writing files to storage.
  final writeFileTool = Tool(
    name: 'write_file',
    description: 'Write a file to the virtual filesystem with automatic versioning',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The file path relative to the worktree',
        ),
        'content': Schema.string(
          description: 'The file content (text or base64 encoded for binary)',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
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
        'path': Schema.string(
          description: 'The file path relative to the worktree',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
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
        'path': Schema.string(
          description: 'The directory path relative to the worktree',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for exporting files as a ZIP archive.
  final exportZipTool = Tool(
    name: 'export_zip',
    description: 'Export files from a directory as a ZIP archive',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The directory path to export',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['path'],
    ),
  );

  /// Implementation of write_file tool.
  FutureOr<CallToolResult> _writeFile(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final content = request.arguments!['content'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final contentBytes = utf8.encode(content);
      final id = await _storage.writeFile(path, contentBytes, worktree: worktree);

      return CallToolResult(
        content: [
          TextContent(
            text: 'File written successfully with ID: $id',
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
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final record = await _storage.readFile(path, worktree: worktree);

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

      final content = utf8.decode(record.content);
      return CallToolResult(
        content: [
          TextContent(
            text: 'File: ${record.path}\n'
                'Version: ${record.version}\n'
                'ID: ${record.id}\n'
                'Created: ${record.createdAt}\n\n'
                '$content',
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
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final files = await _storage.listDirectory(path, worktree: worktree);

      if (files.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No files found in directory: $path',
            ),
          ],
        );
      }

      final listing = files.map((f) => '${f.path} (v${f.version}, ${f.id})').join('\n');
      return CallToolResult(
        content: [
          TextContent(
            text: 'Files in $path:\n$listing',
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

  /// Implementation of export_zip tool.
  FutureOr<CallToolResult> _exportZip(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    // Placeholder implementation
    return CallToolResult(
      content: [
        TextContent(
          text: 'ZIP export functionality will be implemented in future version.\n'
              'Requested path: $path\n'
              'Worktree: ${worktree ?? "none"}',
        ),
      ],
    );
  }

  void dispose() {
    _storage.close();
  }
}
