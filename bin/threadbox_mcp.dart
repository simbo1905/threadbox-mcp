// Copyright (c) 2025, ThreadBox MCP contributors.

/// Main entry point for ThreadBox MCP server.
library;

import 'dart:io' as io;

import 'package:dart_mcp/stdio.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

Future<void> main() async {
  final dbPath = io.Platform.environment['THREADBOX_DB'] ?? 'threadbox.db';
  final storage = await FileStorage.open(dbPath);

  ThreadBoxServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    storage,
  );

  io.stderr.writeln('ThreadBox MCP Server started. Database: $dbPath');
}
