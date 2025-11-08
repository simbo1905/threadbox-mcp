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
    // Register MCP tools for file operations
    registerTool(writeFileTool, _writeFile);
    registerTool(readFileTool, _readFile);
    registerTool(listDirectoryTool, _listDirectory);
    registerTool(moveFileTool, _moveFile);
    registerTool(renameFileTool, _renameFile);
    registerTool(copyFileTool, _copyFile);
    registerTool(deleteFileTool, _deleteFile);
    registerTool(createDirectoryTool, _createDirectory);
    registerTool(getMetadataTool, _getMetadata);
    registerTool(getFileHistoryTool, _getFileHistory);
    registerTool(listWorktreesTool, _listWorktrees);
    registerTool(existsTool, _exists);
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
        'metadata': Schema.string(
          description: 'Optional custom metadata as JSON string',
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
        'recursive': Schema.bool(
          description: 'Whether to list files recursively (default: false)',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for moving files or directories.
  final moveFileTool = Tool(
    name: 'move_file',
    description: 'Move a file or directory to a new location',
    inputSchema: Schema.object(
      properties: {
        'source': Schema.string(
          description: 'The source path',
        ),
        'destination': Schema.string(
          description: 'The destination path',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['source', 'destination'],
    ),
  );

  /// Tool for renaming files or directories.
  final renameFileTool = Tool(
    name: 'rename_file',
    description: 'Rename a file or directory',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The path to rename',
        ),
        'new_name': Schema.string(
          description: 'The new name (without path)',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['path', 'new_name'],
    ),
  );

  /// Tool for copying files or directories.
  final copyFileTool = Tool(
    name: 'copy_file',
    description: 'Copy a file or directory to a new location',
    inputSchema: Schema.object(
      properties: {
        'source': Schema.string(
          description: 'The source path',
        ),
        'destination': Schema.string(
          description: 'The destination path',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['source', 'destination'],
    ),
  );

  /// Tool for deleting files or directories.
  final deleteFileTool = Tool(
    name: 'delete_file',
    description: 'Delete a file or directory (marks as deleted, preserves history)',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The path to delete',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
        'recursive': Schema.bool(
          description: 'Whether to delete directories recursively (default: false)',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for creating directories.
  final createDirectoryTool = Tool(
    name: 'create_directory',
    description: 'Create a directory in the virtual filesystem',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The directory path to create',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
        'metadata': Schema.string(
          description: 'Optional custom metadata as JSON string',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for getting file/directory metadata.
  final getMetadataTool = Tool(
    name: 'get_metadata',
    description: 'Get metadata for a file or directory',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The path to get metadata for',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for getting file history.
  final getFileHistoryTool = Tool(
    name: 'get_file_history',
    description: 'Get version history for a file',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The file path',
        ),
        'worktree': Schema.string(
          description: 'Optional Git worktree identifier for isolation',
        ),
      },
      required: ['path'],
    ),
  );

  /// Tool for listing all worktrees.
  final listWorktreesTool = Tool(
    name: 'list_worktrees',
    description: 'List all Git worktrees in the database',
    inputSchema: Schema.object(
      properties: {},
      required: [],
    ),
  );

  /// Tool for checking if a path exists.
  final existsTool = Tool(
    name: 'exists',
    description: 'Check if a file or directory exists',
    inputSchema: Schema.object(
      properties: {
        'path': Schema.string(
          description: 'The path to check',
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
    final metadata = request.arguments!['metadata'] as String?;

    try {
      final contentBytes = utf8.encode(content);
      final id = await _storage.writeFile(path, contentBytes, worktree: worktree, metadata: metadata);

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

      final content = record.isDirectory ? '[DIRECTORY]' : utf8.decode(record.content);
      return CallToolResult(
        content: [
          TextContent(
            text: 'File: ${record.path}\n'
                'Type: ${record.isDirectory ? "Directory" : "File"}\n'
                'Version: ${record.version}\n'
                'ID: ${record.id}\n'
                'Created: ${record.createdAt}\n'
                '${record.metadata != null ? "Metadata: ${record.metadata}\n" : ""}'
                '${!record.isDirectory ? "\n$content" : ""}',
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
    final recursive = request.arguments!['recursive'] as bool? ?? false;

    try {
      final files = await _storage.listDirectory(path, worktree: worktree, recursive: recursive);

      if (files.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No files found in directory: $path',
            ),
          ],
        );
      }

      final listing = files.map((f) => 
        '${f.isDirectory ? "[DIR]" : "[FILE]"} ${f.path} (v${f.version}, ${f.id})'
      ).join('\n');
      
      return CallToolResult(
        content: [
          TextContent(
            text: 'Files in $path (${recursive ? "recursive" : "non-recursive"}):\n$listing',
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

  /// Implementation of move_file tool.
  FutureOr<CallToolResult> _moveFile(CallToolRequest request) async {
    final source = request.arguments!['source'] as String;
    final destination = request.arguments!['destination'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final id = await _storage.moveFile(source, destination, worktree: worktree);

      return CallToolResult(
        content: [
          TextContent(
            text: 'Moved $source to $destination successfully (new ID: $id)',
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
    final path = request.arguments!['path'] as String;
    final newName = request.arguments!['new_name'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final id = await _storage.renameFile(path, newName, worktree: worktree);

      return CallToolResult(
        content: [
          TextContent(
            text: 'Renamed $path to $newName successfully (new ID: $id)',
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

  /// Implementation of copy_file tool.
  FutureOr<CallToolResult> _copyFile(CallToolRequest request) async {
    final source = request.arguments!['source'] as String;
    final destination = request.arguments!['destination'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final id = await _storage.copyFile(source, destination, worktree: worktree);

      return CallToolResult(
        content: [
          TextContent(
            text: 'Copied $source to $destination successfully (new ID: $id)',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error copying file: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of delete_file tool.
  FutureOr<CallToolResult> _deleteFile(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;
    final recursive = request.arguments!['recursive'] as bool? ?? false;

    try {
      await _storage.deleteFile(path, worktree: worktree, recursive: recursive);

      return CallToolResult(
        content: [
          TextContent(
            text: 'Deleted $path successfully',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error deleting file: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of create_directory tool.
  FutureOr<CallToolResult> _createDirectory(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;
    final metadata = request.arguments!['metadata'] as String?;

    try {
      final id = await _storage.createDirectory(path, worktree: worktree, metadata: metadata);

      return CallToolResult(
        content: [
          TextContent(
            text: 'Directory created successfully with ID: $id',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error creating directory: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of get_metadata tool.
  FutureOr<CallToolResult> _getMetadata(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final metadata = await _storage.getMetadata(path, worktree: worktree);

      if (metadata == null) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'File or directory not found: $path',
            ),
          ],
          isError: true,
        );
      }

      final metadataJson = jsonEncode(metadata.toJson());
      return CallToolResult(
        content: [
          TextContent(
            text: 'Metadata for $path:\n$metadataJson',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error getting metadata: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of get_file_history tool.
  FutureOr<CallToolResult> _getFileHistory(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final history = await _storage.getFileHistory(path, worktree: worktree);

      if (history.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No history found for: $path',
            ),
          ],
        );
      }

      final historyText = history.map((record) => 
        'Version ${record.version} (${record.id}): Created ${record.createdAt}'
      ).join('\n');

      return CallToolResult(
        content: [
          TextContent(
            text: 'History for $path:\n$historyText',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error getting file history: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of list_worktrees tool.
  FutureOr<CallToolResult> _listWorktrees(CallToolRequest request) async {
    try {
      final worktrees = await _storage.listWorktrees();

      if (worktrees.isEmpty) {
        return CallToolResult(
          content: [
            TextContent(
              text: 'No worktrees found',
            ),
          ],
        );
      }

      return CallToolResult(
        content: [
          TextContent(
            text: 'Worktrees:\n${worktrees.join("\n")}',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error listing worktrees: $e',
          ),
        ],
        isError: true,
      );
    }
  }

  /// Implementation of exists tool.
  FutureOr<CallToolResult> _exists(CallToolRequest request) async {
    final path = request.arguments!['path'] as String;
    final worktree = request.arguments!['worktree'] as String?;

    try {
      final exists = await _storage.exists(path, worktree: worktree);

      return CallToolResult(
        content: [
          TextContent(
            text: exists ? 'Path exists: $path' : 'Path does not exist: $path',
          ),
        ],
      );
    } catch (e) {
      return CallToolResult(
        content: [
          TextContent(
            text: 'Error checking if path exists: $e',
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
