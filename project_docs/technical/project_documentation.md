# Tandem - Technical Documentation

## 1. Overview
Tandem is a native macOS utility designed to keep two folders in sync with each other. It provides a robust diff engine, side-by-side tree UI, secure backup capabilities, and support for multiple sync pairs with advanced exclusion rules.

## 2. Requirements
- **Core Functionality:** Keep two folders in sync (Left and Right).
- **Multiple Pairs:** Support configuring and managing multiple folder pairs.
- **Diff Detection:** Accurately detect file states: Same, New, Updated, Deleted, and Clash (conflicts).
- **Exclusion Rules:** Allow users to define subfolders, files, or patterns (glob) to be excluded from the sync process.
- **Sync Triggers:** Support manual, real-time (file system events), and scheduled sync modes.
- **Secure Backup:** Move replaced or deleted files to a secure backup location with timestamp-based naming instead of permanently deleting them.
- **User Interface:** Native macOS side-by-side tree UI, tooltips, right-click context menus, and conflict resolution previews.

## 3. Tech Stack
- **Language:** Swift 6.2.3
- **Platform:** macOS 14.0+ (Apple Silicon / arm64 optimized)
- **UI Framework:** AppKit (Programmatic UI, no Storyboards or SwiftUI)
- **Database:** GRDB.swift 6.x (SQLite)
- **Build System:** Swift Package Manager (SPM) + Makefile
- **Packaging & Signing:** Custom shell script (`scripts/bundle.sh`) for assembling the `.app` bundle and applying Ad-hoc codesigning.

## 4. Architecture & Technical Decisions
- **SPM Structure:** The project is split into a `TandemCore` library target (containing all app logic, UI, and data models) and a `Tandem` executable target (containing only `main.swift`). This enforces clean separation and improves testability.
- **Database (GRDB):** Chosen for its robust SQLite wrapper, thread-safe `DatabasePool`, and reactive `ValueObservation` capabilities. The database stores `SyncPair`, `TrackedFile`, `BackupRecord`, and `ExclusionRule` models.
- **Diff Engine:** Uses a custom `FileScanner` that recursively walks directories using `FileManager.enumerator`, applies exclusion rules, and computes SHA-256 checksums for accurate diffing. The `DiffEngine` compares left and right scans to produce a `DiffSummary`.
- **File Watching:** Utilizes the native macOS FSEvents C API (`FSEventWatcher`) for real-time sync triggers, debounced to prevent excessive sync operations. A `ScheduledTicker` handles time-based syncs.
- **Conflict Resolution:** When a file is modified on both sides, it is marked as a `.clash`. The user is presented with a `ConflictResolutionViewController` utilizing `QLPreviewView` to decide which version to keep, or to keep both (renaming one with a timestamp).

## 5. UI/UX Decisions
- **AppKit over SwiftUI:** AppKit was chosen to provide a deeply native, high-performance macOS experience, specifically for complex components like `NSOutlineView` (tree views) and `NSSplitViewController`.
- **Programmatic UI:** No Storyboards or XIBs are used. All views and Auto Layout constraints are defined in code for better version control and modularity.
- **Main Window Layout:** Uses an `NSSplitViewController` with a sidebar (`SyncPairListVC`) for navigation and a detail view (`PairDetailViewController`) for the active sync pair.
- **Sidebar Controls:** Standard macOS patterns are used, such as an `NSSegmentedControl` with `+` and `-` buttons at the bottom of the sidebar for adding and removing sync pairs.
- **Tree View:** The `TreeViewController` uses an `NSOutlineView` with columns for Name, Status, Size, and Modified Date. It includes right-click context menus for granular file operations (Sync File, Force Copy, Resolve Clash, Add to Exclusions, Reveal in Finder).

## 6. Data Models & Persistence
- **`SyncPair`:** Represents a configured pair of folders, including paths, sync mode, schedule interval, and backup settings.
- **`TrackedFile`:** Represents a file tracked by the sync engine, including its relative path, checksum, and which side it belongs to.
- **`BackupRecord`:** Logs files that were moved to the backup location, including original path, backup path, and timestamp.
- **`ExclusionRule`:** Defines rules for ignoring files/folders during the scan phase. Supports exact filename, relative filepath, folder name, and glob patterns (using `fnmatch`).

## 7. Build & Deployment
- **VS Code Workflow:** The project is designed to be developed entirely within Visual Studio Code, using Xcode only as a CLI toolchain.
- **Makefile:** Provides targets for `build`, `test`, `app`, `run`, `install`, and `clean`.
- **App Bundling:** The `make app` command triggers `scripts/bundle.sh`, which creates the `Tandem.app` directory structure, copies the compiled binary and resources (like `Info.plist`), injects the Git version, and performs ad-hoc codesigning (`codesign --force --deep --sign -`).
