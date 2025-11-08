// Copyright (c) 2025, ThreadBox MCP contributors.

/// Main entry point for ThreadBox MCP server and CLI.
library;

import 'dart:io' as io;
import 'package:args/args.dart';
import 'package:dart_mcp/stdio.dart';
import 'package:threadbox_mcp/src/git_utils.dart';
import 'package:threadbox_mcp/src/server.dart';
import 'package:threadbox_mcp/src/storage.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag('mcp-server', help: 'Run as MCP server')
    ..addOption('session', help: 'Session ID for CLI operations')
    ..addFlag('zip', help: 'Export session as ZIP')
    ..addFlag('dump', help: 'Dump all session state')
    ..addOption('data-path', help: 'Override data directory path');

  final results = parser.parse(args);

  // Get data path
  final dataPath = results['data-path'] as String? ?? getDefaultDataPath();
  await ensureDataDirectory(dataPath);
  final dbPath = path.join(dataPath, 'threadbox.db');

  if (results['mcp-server'] as bool) {
    // Run as MCP server
    final storage = FileStorage(dbPath);
    final sessionId = await detectSessionId();
    
    ThreadBoxServer(
      stdioChannel(input: io.stdin, output: io.stdout),
      storage,
      dataPath,
    );

    io.stderr.writeln('ThreadBox MCP Server started.');
    io.stderr.writeln('Session ID: $sessionId');
    io.stderr.writeln('Database: $dbPath');
  } else if (results['zip'] as bool) {
    // Export session as ZIP
    final sessionId = results['session'] as String?;
    if (sessionId == null) {
      io.stderr.writeln('Error: --session is required with --zip');
      io.exit(1);
    }

    await _exportSessionZip(sessionId, dbPath, dataPath);
  } else if (results['dump'] as bool) {
    // Dump all sessions
    await _dumpSessions(dbPath);
  } else {
    // Show help
    io.stdout.writeln('ThreadBox - Virtual file system for agent artefacts\n');
    io.stdout.writeln('Usage:');
    io.stdout.writeln('  threadbox --mcp-server              Run as MCP server');
    io.stdout.writeln('  threadbox --session <id> --zip       Export session as ZIP');
    io.stdout.writeln('  threadbox --dump                    Dump all session state');
    io.stdout.writeln('\nOptions:');
    io.stdout.writeln(parser.usage);
  }
}

Future<void> _exportSessionZip(String sessionId, String dbPath, String dataPath) async {
  final storage = FileStorage(dbPath);
  try {
    final files = await storage.getSessionFiles(sessionId);

    if (files.isEmpty) {
      io.stderr.writeln('No files found in session: $sessionId');
      io.exit(1);
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
    final zipPath = path.join(dataPath, zipFileName);
    
    final zipFile = io.File(zipPath);
    await zipFile.writeAsBytes(zipData!);

    io.stdout.writeln('Exported session to: $zipPath');
  } finally {
    await storage.close();
  }
}

Future<void> _dumpSessions(String dbPath) async {
  final storage = FileStorage(dbPath);
  try {
    final sessions = await storage.getAllSessions();
    
    io.stdout.writeln('Sessions:');
    for (final sessionId in sessions) {
      io.stdout.writeln('  $sessionId');
      final files = await storage.getSessionFiles(sessionId);
      for (final file in files) {
        io.stdout.writeln('    ${file.path} (v${file.version}, ${file.id})');
      }
    }
  } finally {
    await storage.close();
  }
}
