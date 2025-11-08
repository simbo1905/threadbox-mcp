// Copyright (c) 2025, ThreadBox MCP contributors.

/// Configuration management for ThreadBox.
library;

import 'dart:io';
import 'package:path/path.dart' as p;

/// Configuration for ThreadBox.
class ThreadBoxConfig {
  /// Default data directory path.
  static String get defaultDataPath {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) {
      throw Exception('Could not determine home directory');
    }
    return p.join(home, '.threadbox', 'data');
  }

  /// Get the database path for the given data directory.
  static String getDatabasePath(String dataPath) {
    return p.join(dataPath, 'threadbox.db');
  }

  /// Ensure the data directory exists.
  static Future<void> ensureDataDirectory(String dataPath) async {
    final dir = Directory(dataPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }
}
