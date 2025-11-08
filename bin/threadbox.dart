// Copyright (c) 2025, ThreadBox MCP contributors.

/// Main entry point for ThreadBox - supports both MCP server and CLI modes.
library;

import 'dart:io' as io;
import 'dart:convert';
import 'package:args/args.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:threadbox_mcp/threadbox_mcp.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'mcp-server',
      help: 'Run as MCP server (stdio mode)',
      negatable: false,
    )
    ..addOption(
      'session',
      help: 'Session ID for CLI operations',
    )
    ..addFlag(
      'zip',
      help: 'Export session as ZIP file',
      negatable: false,
    )
    ..addFlag(
      'dump',
      help: 'Dump all session information',
      negatable: false,
    )
    ..addOption(
      'data-path',
      help: 'Custom data directory path (default: ~/.threadbox/data)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message',
      negatable: false,
    );

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    io.stderr.writeln('Error parsing arguments: $e');
    io.stderr.writeln(parser.usage);
    io.exit(1);
  }

  if (args['help'] as bool) {
    _printHelp(parser);
    return;
  }

  // Determine data path
  final dataPath = args['data-path'] as String? ?? ThreadBoxConfig.defaultDataPath;
  await ThreadBoxConfig.ensureDataDirectory(dataPath);
  final dbPath = ThreadBoxConfig.getDatabasePath(dataPath);

  // MCP Server mode
  if (args['mcp-server'] as bool) {
    await _runMcpServer(dbPath);
    return;
  }

  // CLI mode - requires storage
  final storage = await FileStorage.create(dbPath);

  try {
    // Dump command
    if (args['dump'] as bool) {
      await _dumpSessions(storage);
      return;
    }

    // Export ZIP command
    if (args['zip'] as bool) {
      final sessionId = args['session'] as String?;
      if (sessionId == null) {
        io.stderr.writeln('Error: --session is required with --zip');
        io.exit(1);
      }
      await _exportSessionZip(storage, sessionId);
      return;
    }

    // No valid command specified
    io.stderr.writeln('Error: No valid command specified');
    io.stderr.writeln('Use --help for usage information');
    io.exit(1);
  } finally {
    await storage.close();
  }
}

void _printHelp(ArgParser parser) {
  print('''
ThreadBox - Virtual filesystem for AI agent artifacts

Usage:
  threadbox --mcp-server [--data-path PATH]    Run as MCP server
  threadbox --session ID --zip [--data-path PATH]  Export session to ZIP
  threadbox --dump [--data-path PATH]          Dump all sessions

Options:
${parser.usage}

Examples:
  # Run as MCP server (auto-detects Git worktree)
  threadbox --mcp-server

  # Export session to ZIP
  threadbox --session my-feature --zip

  # Use custom data directory
  threadbox --mcp-server --data-path /tmp/threadbox

  # Dump all session information
  threadbox --dump
''');
}

Future<void> _runMcpServer(String dbPath) async {
  // Initialize storage
  final storage = await FileStorage.create(dbPath);

  // Detect session ID from Git worktree
  final sessionId = getSessionId();

  // Create and start the MCP server connected to stdio
  ThreadBoxServer(
    stdioChannel(input: io.stdin, output: io.stdout),
    storage,
    defaultSessionId: sessionId,
  );

  io.stderr.writeln('ThreadBox MCP Server started');
  io.stderr.writeln('  Database: $dbPath');
  io.stderr.writeln('  Session ID: $sessionId');
}

Future<void> _dumpSessions(FileStorage storage) async {
  try {
    final dump = await storage.dumpSessions();
    final jsonOutput = JsonEncoder.withIndent('  ').convert(dump);
    print(jsonOutput);
  } catch (e) {
    io.stderr.writeln('Error dumping sessions: $e');
    io.exit(1);
  }
}

Future<void> _exportSessionZip(FileStorage storage, String sessionId) async {
  try {
    io.stderr.writeln('Exporting session: $sessionId');
    final zipPath = await storage.exportSessionZip(sessionId);
    print('Created: $zipPath');
  } catch (e) {
    io.stderr.writeln('Error exporting session: $e');
    io.exit(1);
  }
}
