// Copyright (c) 2025, ThreadBox MCP contributors.

/// Main entry point for ThreadBox MCP server.
library;

import 'dart:io' as io;
import 'package:dart_mcp/stdio.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

Future<void> main() async {
  // Initialize storage with default database path
  final dbPath = io.Platform.environment['THREADBOX_DB'] ?? 'threadbox.db';
  final storage = FileStorage(dbPath);

  // Create and start the MCP server connected to stdio
  ThreadBoxServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    storage,
  );

  io.stderr.writeln('ThreadBox MCP Server started. Database: $dbPath');
}
