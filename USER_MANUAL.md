# FolderSync — User Manual

**Version 1.0** · macOS 14 (Sonoma) and later

---

## Table of Contents

1. [Overview](#1-overview)
2. [Installation](#2-installation)
3. [Interface Overview](#3-interface-overview)
4. [Managing Sync Pairs](#4-managing-sync-pairs)
5. [Understanding File States](#5-understanding-file-states)
6. [Running a Sync](#6-running-a-sync)
7. [Sync Modes](#7-sync-modes)
8. [Resolving Conflicts (Clashes)](#8-resolving-conflicts-clashes)
9. [Exclusion Rules](#9-exclusion-rules)
10. [Backup & History](#10-backup--history)
11. [Preferences](#11-preferences)
12. [Keyboard Shortcuts & Context Menus](#12-keyboard-shortcuts--context-menus)
13. [Troubleshooting](#13-troubleshooting)
14. [Privacy & Security](#14-privacy--security)

---

## 1. Overview

FolderSync keeps two folders — **Left** and **Right** — in sync with each other. It shows you exactly what has changed before anything is written, lets you exclude files or folders you don't want synced, and automatically moves any replaced or deleted file to a safe backup location instead of discarding it permanently.

**Key capabilities:**
- Visual diff tree showing every file state side-by-side
- Three sync triggers: Manual, Real-Time (instant), and Scheduled
- Conflict detection and interactive resolution with Quick Look preview
- Flexible exclusion rules (exact names, paths, globs)
- Full backup history with point-in-time restore

---

## 2. Installation

### From a DMG

1. Download **FolderSync-x.x.x.dmg** from the [Releases](https://github.com/YOUR_USERNAME/FolderSync/releases) page.
2. Double-click the DMG to mount it.
3. Drag **FolderSync.app** into the **Applications** shortcut.
4. Eject the DMG.
5. Open **FolderSync** from Launchpad or `/Applications`.

> **First-launch Gatekeeper prompt:** Because FolderSync is distributed ad-hoc signed, macOS may show a security prompt. Right-click (or Control-click) the app in Finder and choose **Open**, then click **Open** in the dialog. You only need to do this once.

### Granting Folder Access

FolderSync needs Full Disk Access or at minimum access to the folders you intend to sync. If you see permission errors:

1. Open **System Settings → Privacy & Security → Files and Folders** (or **Full Disk Access**).
2. Add **FolderSync** and enable it.

---

## 3. Interface Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Toolbar: [Scan] [Sync] [Stop]          Sync Pair Name / Status │
├────────────┬────────────────────────────────────────────────────┤
│            │  LEFT PATH          │  RIGHT PATH                  │
│  Sidebar   │─────────────────────────────────────────────────── │
│            │  Name  │ Status │ Size │ Modified │ …              │
│  Pair 1  ◀ │  ▸ docs/                                           │
│  Pair 2    │    README.md │ Same  │ 12 KB │ …                   │
│  Pair 3    │    notes.txt │ New ← │  4 KB │ …                   │
│            │    photo.jpg │ Clash │ 2.1 MB│ …                   │
│  [+] [−]   │                                                     │
└────────────┴────────────────────────────────────────────────────┘
```

| Area | Description |
|---|---|
| **Sidebar** | Lists all configured sync pairs. Click to select. `+` adds a new pair, `−` removes the selected pair. |
| **Toolbar** | Scan (refresh diff), Sync (apply changes), Stop (cancel operation). |
| **Diff Tree** | Side-by-side tree of all files and folders with their current sync state. |
| **Status Bar** | Shows counts of changed files, last sync time, and current operation progress. |

---

## 4. Managing Sync Pairs

### Adding a Pair

1. Click the **`+`** button at the bottom of the sidebar.
2. In the sheet that appears, click **Choose…** next to **Left Folder** and select a folder.
3. Click **Choose…** next to **Right Folder** and select the other folder.
4. Give the pair a descriptive name.
5. Choose a **Sync Mode** (see [§7 Sync Modes](#7-sync-modes)).
6. Click **Add**.

FolderSync immediately performs an initial scan.

### Renaming a Pair

Double-click the pair name in the sidebar to rename it inline.

### Removing a Pair

Select the pair in the sidebar and click **`−`**. This removes the configuration and all tracked state, but **does not delete any files**.

### Pair Detail Settings

With a pair selected, click the **⚙ Settings** button in the toolbar (or the gear icon in the detail view) to adjust per-pair settings including sync direction, backup location, and schedule interval.

---

## 5. Understanding File States

Each file in the diff tree carries one of the following states:

| State | Icon | Meaning |
|---|---|---|
| **Same** | ✓ (grey) | File is identical on both sides. |
| **New →** | ➜ (green) | File exists only on the Left; will be copied to Right on sync. |
| **← New** | ← (green) | File exists only on the Right; will be copied to Left on sync. |
| **Updated →** | ↑ (blue) | Left version is newer; will overwrite Right on sync. |
| **← Updated** | ↓ (blue) | Right version is newer; will overwrite Left on sync. |
| **Deleted** | ✕ (red) | File was deleted on one side; the other side will be updated to match. |
| **Clash** | ⚠ (orange) | Both sides were modified since the last sync. Requires manual resolution. |

> **Tip:** Click the column headers to sort by state, name, size, or date.

---

## 6. Running a Sync

### Manual Sync

1. Select a sync pair.
2. Click **Scan** to refresh the diff tree (or wait for it to refresh automatically).
3. Review the file states.
4. Click **Sync** to apply all pending changes, or right-click individual files for per-file actions.

### What Happens During Sync

- **New / Updated files** are copied from the source side to the destination.
- **Deleted files** on one side are removed from the other side.
- **Before overwriting or deleting**, the existing file is moved to the **backup location** (never permanently erased).
- **Clash files** are skipped — you must resolve them first (see [§8](#8-resolving-conflicts-clashes)).

---

## 7. Sync Modes

Configure the sync mode per pair in the pair's **Settings** sheet.

### Manual

The diff tree is updated whenever you click **Scan**. No automatic sync occurs. Best for intentional, reviewed syncs.

### Real-Time

Uses macOS FSEvents to detect file system changes instantly. A brief debounce delay (default 2 seconds) prevents excessive syncs during rapid writes. FolderSync will automatically scan and optionally sync after changes are detected.

> **Note:** Real-time mode does not automatically sync — it triggers a fresh scan. You still click **Sync** to apply changes (unless auto-sync is enabled in Preferences).

### Scheduled

Performs a scan (and optionally a sync) at a regular interval you specify (e.g. every 15 minutes, every hour). Useful for backup-style workflows where you want periodic synchronisation without watching every keystroke.

---

## 8. Resolving Conflicts (Clashes)

A **Clash** occurs when the same file has been modified on both sides since the last successful sync.

### Opening the Conflict Resolver

- Right-click a **Clash** file in the tree → **Resolve Clash…**
- Or select the file and press **Space** to Quick Look, then use the context menu.

### Resolution Options

The Conflict Resolution panel shows a side-by-side Quick Look preview of both versions.

| Action | Result |
|---|---|
| **Use Left** | Overwrites the Right file with the Left version. The old Right file is backed up. |
| **Use Right** | Overwrites the Left file with the Right version. The old Left file is backed up. |
| **Keep Both** | Renames the Right version with a timestamp suffix and copies both files to both sides. |
| **Skip** | Leaves the clash unresolved. The file will remain marked as Clash. |

---

## 9. Exclusion Rules

Exclusion rules tell FolderSync to ignore certain files or folders during the scan entirely.

### Adding an Exclusion Rule

1. Select a sync pair.
2. Click **Exclusions** in the toolbar.
3. Click **`+`** and configure the rule.

### Rule Types

| Type | Example | What it matches |
|---|---|---|
| **Filename** | `.DS_Store` | Any file with exactly this name, anywhere in the tree. |
| **Folder Name** | `node_modules` | Any folder with this name (and all its contents). |
| **Relative Path** | `build/output.log` | A specific path relative to the sync root. |
| **Glob Pattern** | `*.tmp`, `cache/**` | Files matching the glob (uses `fnmatch`). |

### Quick-Add from Tree

Right-click any file in the diff tree → **Add to Exclusions**. FolderSync pre-fills the rule with the file's name and lets you choose the rule type before saving.

### Managing Rules

Rules are listed in the Exclusions panel. Select a rule and click **`−`** to remove it. Changes take effect on the next scan.

---

## 10. Backup & History

### How Backups Work

Every time FolderSync would overwrite or delete a file, it first moves the existing file to a **backup location** with a timestamp suffix:

```
~/Library/Application Support/FolderSync/Backups/
  └── PairName/
        └── 2026-02-28T14-32-10_notes.txt
```

The backup location can be changed per pair in **Pair Settings → Backup Location**.

### Viewing Backup History

Click **History** in the toolbar to open the Backup History panel. It shows:
- Original file path
- Backup file path
- Timestamp
- Which sync operation caused the backup

### Restoring a File

1. Open **History**.
2. Find the version you want.
3. Right-click → **Restore to Original Location** (overwrites the current file) or **Reveal in Finder** to copy it manually.

---

## 11. Preferences

Open **FolderSync → Preferences** (⌘,).

| Setting | Description |
|---|---|
| **Auto-Sync on Detection** | In Real-Time mode, automatically sync immediately after a change is detected (no manual Sync click required). |
| **Show Same Files** | Whether to display unchanged files in the diff tree. |
| **Default Backup Location** | The base path used for backups when a pair hasn't specified its own. |
| **Debounce Interval** | How long (in seconds) to wait after a file-system event before triggering a scan (Real-Time mode). |
| **Launch at Login** | Register FolderSync as a login item. |

---

## 12. Keyboard Shortcuts & Context Menus

### Global Shortcuts

| Shortcut | Action |
|---|---|
| ⌘S | Scan selected pair |
| ⌘R | Sync selected pair |
| ⌘, | Open Preferences |
| ⌘W | Close front window |

### Right-Click Context Menu (Diff Tree)

| Action | Description |
|---|---|
| **Sync File** | Sync this individual file immediately. |
| **Force Copy →** | Copy Left → Right, regardless of state. |
| **Force Copy ←** | Copy Right → Left, regardless of state. |
| **Resolve Clash…** | Open the conflict resolution panel. |
| **Add to Exclusions** | Create an exclusion rule for this file. |
| **Reveal in Finder** | Show the Left or Right copy in Finder. |

---

## 13. Troubleshooting

### App Won't Open ("App is damaged" or Gatekeeper blocked)

This happens with ad-hoc signed builds. In Terminal:

```bash
xattr -cr /Applications/FolderSync.app
```

Then try opening again.

### Scan Is Slow on Large Folders

FolderSync computes SHA-256 checksums for every file to detect changes accurately. On first scan of a very large folder (e.g. hundreds of thousands of files), this may take several minutes. Subsequent scans are faster because only modified files are re-checksummed.

To speed things up:
- Add exclusion rules for `node_modules`, `.git`, `build` folders, or other large generated directories.
- Use **Scheduled** mode with a longer interval rather than **Real-Time** for very large trees.

### Permission Denied Errors

FolderSync needs read/write access to both folders and the backup location. Check:

1. **System Settings → Privacy & Security → Files and Folders** — ensure FolderSync has access.
2. The user account running FolderSync owns or has write permissions for both folders.

### Files Re-Appear After Deletion

If a sync pair's mode is **bidirectional** and you delete a file on one side, FolderSync may restore it from the other side. To permanently delete a file from both sides, first delete it from both Left and Right, then run a scan and sync (both sides will show it as absent, and the diff engine will leave it deleted).

### Clashes That Can't Be Resolved

If Quick Look shows blank previews (certain binary formats), use **Reveal in Finder** to open both versions in their native application, then choose **Use Left** or **Use Right** manually.

### Checking Logs

FolderSync writes diagnostic messages to the macOS unified log. To view them:

```bash
log show --last 5m --predicate 'processImagePath CONTAINS[c] "foldersync"' --style compact
```

Or open **Console.app** and filter for `FolderSync`.

---

## 14. Privacy & Security

- FolderSync does **not** connect to the internet. There are no analytics, telemetry, or cloud services.
- All data (sync pair configuration, tracked file records, backup history) is stored locally in an SQLite database at `~/Library/Application Support/FolderSync/foldersync.db`.
- Backup files are stored locally at the path you configure (default: `~/Library/Application Support/FolderSync/Backups/`).
- File checksums (SHA-256) are stored in the database solely for change detection; they are never transmitted anywhere.

---

*For support, bug reports, or feature requests, please open an issue on [GitHub](https://github.com/YOUR_USERNAME/FolderSync/issues).*
