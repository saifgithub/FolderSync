# FolderSync

> A native macOS folder-synchronisation utility with a side-by-side diff tree, real-time file watching, secure backups, and multi-pair support.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?logo=apple)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## Screenshots

> _Add screenshots here once the app is launched._

---

## Features

| Feature | Description |
|---|---|
| **Multiple Sync Pairs** | Configure and manage as many folder pairs as you need from a single sidebar. |
| **Side-by-Side Diff Tree** | Instantly visualise which files are New, Updated, Deleted, Same, or in Conflict (Clash). |
| **Sync Modes** | Manual, Real-Time (FSEvents), or Scheduled (interval-based). |
| **Conflict Resolution** | Quick Look preview of both file versions; keep Left, Right, or both. |
| **Exclusion Rules** | Exclude by filename, relative path, folder name, or glob pattern (`fnmatch`). |
| **Secure Backup** | Replaced/deleted files are moved to a timestamped backup folder — never permanently deleted. |
| **Native AppKit UI** | Programmatic NSOutlineView tree, NSSplitView sidebar, right-click context menus, tooltips. |
| **Lightweight** | SQLite persistence via [GRDB](https://github.com/groue/GRDB.swift); zero heavy frameworks. |

---

## Requirements

- **macOS 14.0 (Sonoma)** or later (Apple Silicon & Intel)
- **Xcode Command Line Tools** (for building from source)

---

## Installation

### Pre-built DMG (recommended)

1. Download the latest **FolderSync-x.x.x.dmg** from the [Releases](../../releases) page.
2. Open the DMG and drag **FolderSync.app** to your `/Applications` folder.
3. Right-click → **Open** on first launch (Gatekeeper prompt for ad-hoc signed builds).

### Build from source

```bash
git clone https://github.com/saifgithub/FolderSync.git
cd FolderSync
make app-rel          # release build → dist/FolderSync.app
open dist/FolderSync.app
```

Or install directly to `/Applications`:

```bash
make install
```

---

## Building

| Command | Description |
|---|---|
| `make build` | Debug build (Swift Package Manager) |
| `make release` | Release build |
| `make app` | Assemble `dist/FolderSync.app` (debug, ad-hoc signed) |
| `make app-rel` | Assemble `dist/FolderSync.app` (release, ad-hoc signed) |
| `make run` | Build debug app then open it |
| `make test` | Run unit tests |
| `make install` | Release-build and copy to `/Applications` |
| `make clean` | Remove build artefacts and `dist/` |

### Creating a signed & notarised DMG for distribution

```bash
# Ad-hoc signed DMG (no Apple account required)
./scripts/sign_and_dmg.sh

# Developer-signed & notarised DMG
CERT="Developer ID Application: Your Name (TEAMID)" \
APPLE_ID="you@example.com" \
APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
TEAM_ID="YOURTEAMID" \
./scripts/sign_and_dmg.sh
```

See [`scripts/sign_and_dmg.sh`](scripts/sign_and_dmg.sh) for full documentation.

---

## Architecture

```
Sources/
├── FolderSync/          # Executable target — just main.swift
└── FolderSyncCore/      # Library target — all app logic
    ├── App/             # NSApplicationDelegate, app entry point
    ├── Data/            # GRDB database, models (SyncPair, TrackedFile, …)
    ├── SyncEngine/      # FileScanner, DiffEngine, FileOperator, SyncManager, BackupManager
    ├── Watcher/         # FSEventWatcher, ScheduledTicker, WatcherCoordinator
    └── UI/              # All AppKit view controllers (no Storyboards)
```

The project uses Swift Package Manager for dependency management. The only external dependency is [GRDB.swift](https://github.com/groue/GRDB.swift) for SQLite persistence.

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

---

## License

FolderSync is released under the [MIT License](LICENSE).
