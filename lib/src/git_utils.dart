// Copyright (c) 2025, ThreadBox MCP contributors.

/// Git utilities for worktree detection.
library;

import 'dart:io';
import 'package:path/path.dart' as p;

/// Detects the Git worktree name for the current directory.
/// Returns null if not in a Git repository or worktree.
String? detectGitWorktree() {
  try {
    // Try to find .git directory or file
    var currentDir = Directory.current;
    
    while (true) {
      final gitPath = p.join(currentDir.path, '.git');
      final gitEntity = FileSystemEntity.typeSync(gitPath);
      
      if (gitEntity == FileSystemEntityType.directory) {
        // Regular git repo - use directory name
        return p.basename(currentDir.path);
      } else if (gitEntity == FileSystemEntityType.file) {
        // Git worktree - read the .git file to get worktree name
        final gitFile = File(gitPath);
        final content = gitFile.readAsStringSync().trim();
        
        // .git file format: "gitdir: /path/to/main/.git/worktrees/branch-name"
        if (content.startsWith('gitdir:')) {
          final gitdir = content.substring(7).trim();
          // Extract worktree name from path
          final parts = gitdir.split('/');
          if (parts.length >= 2 && parts[parts.length - 2] == 'worktrees') {
            return parts.last; // worktree name
          }
        }
        
        // Fallback to directory name
        return p.basename(currentDir.path);
      }
      
      // Go up one directory
      final parent = currentDir.parent;
      if (parent.path == currentDir.path) {
        // Reached root without finding .git
        break;
      }
      currentDir = parent;
    }
    
    return null;
  } catch (e) {
    // If any error occurs, return null
    return null;
  }
}

/// Generates a session ID based on Git worktree or a generic ID.
/// If in a Git worktree, returns the worktree name.
/// Otherwise, returns "default" or a provided fallback.
String getSessionId([String fallback = 'default']) {
  final worktree = detectGitWorktree();
  return worktree ?? fallback;
}
