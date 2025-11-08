# threadbox-mcp

ThreadBox: Virtual filesystem for AI agent artefacts. A Dart MCP server providing isolated, versioned sandboxes per Git worktree.

## Features

- **MCP Tools**: `write_file`, `read_file`, `list_directory`, `export_zip`
- **Append-only immutability** with full version history
- **UUID-based blob addressing** for unique file identification
- **Git worktree isolation** for session management
- **Async SQLite storage** for reliable persistence

## Installation

Ensure you have Dart SDK installed, then:

```bash
dart pub get
```

## Usage

Run the MCP server:

```bash
dart run bin/threadbox_mcp.dart
```

Or compile to native executable:

```bash
dart compile exe bin/threadbox_mcp.dart -o threadbox_mcp
./threadbox_mcp
```

### Environment Variables

- `THREADBOX_DB`: Path to SQLite database file (default: `threadbox.db`)

## MCP Tools

### write_file
Writes a file to the virtual filesystem with automatic versioning.

**Parameters:**
- `path` (required): File path relative to the worktree
- `content` (required): File content (text or base64 encoded)
- `worktree` (optional): Git worktree identifier for isolation

### read_file
Reads the latest version of a file from the virtual filesystem.

**Parameters:**
- `path` (required): File path relative to the worktree
- `worktree` (optional): Git worktree identifier for isolation

### list_directory
Lists all files in a directory from the virtual filesystem.

**Parameters:**
- `path` (required): Directory path relative to the worktree
- `worktree` (optional): Git worktree identifier for isolation

### export_zip
Exports files from a directory as a ZIP archive (placeholder).

**Parameters:**
- `path` (required): Directory path to export
- `worktree` (optional): Git worktree identifier for isolation

## Development

### Running Tests

```bash
dart test
```

### Linting

```bash
dart analyze
```

## Architecture

- **Storage Layer** (`lib/src/storage.dart`): SQLite-based storage with UUID primary keys
- **MCP Server** (`lib/src/server.dart`): MCP protocol implementation with tool endpoints
- **Main Entry** (`bin/threadbox_mcp.dart`): Server initialization and startup

## License

See LICENSE file for details.

