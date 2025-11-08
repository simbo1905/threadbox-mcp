/// ThreadBox: Virtual filesystem for AI agent artifacts.
///
/// Provides an MCP server with isolated, versioned sandboxes per Git worktree.
/// Features append-only immutability with full history and UUID-based blob addressing.
library;

export 'src/server.dart';
export 'src/storage.dart';
export 'src/git_utils.dart';
export 'src/config.dart';
