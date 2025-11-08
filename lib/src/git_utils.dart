// Copyright (c) 2025, ThreadBox MCP contributors.

/// Utility functions for detecting Git worktree information.
library;

import 'dart:io';

/// Detects the current Git worktree name or returns a default session ID.
Future<String> detectSessionId() async {
  try {
    // Try to get Git worktree name
    final result = await Process.run('git', ['rev-parse', '--abbrev-ref', 'HEAD']);
    if (result.exitCode == 0) {
      final branch = result.stdout.toString().trim();
      if (branch.isNotEmpty && branch != 'HEAD') {
        return branch;
      }
    }
  } catch (_) {
    // Git not available or not in a Git repo
  }

  // Fallback: use a generic session ID
  return 'default';
}

/// Gets the default data directory path.
String getDefaultDataPath() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
  return '$home/.threadbox/data';
}

/// Ensures the data directory exists.
Future<void> ensureDataDirectory(String dataPath) async {
  final dir = Directory(dataPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}
