# Tandem — User Manual

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

Tandem keeps two folders — **Left** and **Right** — in sync with each other. It shows you exactly what has changed before anything is written, lets you exclude files or folders you don't want synced, and automatically moves any replaced or deleted file to a safe backup location instead of discarding it permanently.

**Key capabilities:**
- Visual diff tree showing every file state side-by-side
- Three sync triggers: Manual, Real-Time (instant), and Scheduled
- Conflict detection and interactive resolution with Quick Look preview
- Flexible exclusion rules (exact names, paths, globs)
- Full backup history with point-in-time restore

---

## 2. Installation

### From a DMG

1. Download **Tandem-x.x.x.dmg** from the [Releases](https://github.com/saifgithub/Tandem/releases) page.
2. Double-click the DMG to mount it.
3. Drag **Tandem.app** into the **Applications** shortcut.
4. Eject the DMG.
5. Open **Tandem** from Launchpad or `/Applications`.

> **First-launch Gatekeeper prompt:** Because Tandem is distributed ad-hoc signed, macOS may show a security prompt. Right-click (or Control-click) the app in Finder and choose **Open**, then click **Open** in the dialog. You only need to do this once.

### Granting Folder Access

Tandem needs Full Disk Access or at minimum access to the folders you intend to sync. If you see permission errors:

1. Open **System Settings → Privacy & Security → Files and Folders** (or **Full Disk Access**).
2. Add **Tandem** and enable it.

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

Tandem immediately performs an initial scan.

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

Uses macOS FSEvents to detect file system changes instantly. A brief debounce delay (default 2 seconds) prevents excessive syncs during rapid writes. Tandem will automatically scan and optionally sync after changes are detected.

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

Exclusion rules tell Tandem to ignore certain files or folders entirely during the scan. Excluded paths are never diffed, synced, or backed up.

There are two scopes:

| Scope | Where to find it | Applies to |
|---|---|---|
| **Pair rules** | Pair settings → **Exclusions** tab | One specific sync pair |
| **Global rules** | **Tandem menu → Preferences… → Global Exclusions** tab | Every pair in the app |

---

### Rule Types

| Type | Matches against | Example | What it does |
|---|---|---|---|
| **Filename** | Filename only (any depth) | `.DS_Store` | Skips every file with exactly this name, anywhere in the tree. |
| **Glob Pattern** | Filename only | `*.tmp`, `~$*`, `*.bak` | Skips filenames matching the shell glob (`*` and `?` wildcards, via `fnmatch`). |
| **Folder (subtree)** | Relative path prefix | `node_modules/`, `build/`, `.git/` | Skips the entire subtree rooted at this folder path (trailing `/` optional). |
| **File Path** | Exact relative path | `config/secrets.json` | Skips one specific file relative to the sync root. |

> **Tip:** Hover over the **Type** column header in the Exclusions panel for a quick reference card of all types with examples. Each item in the Type drop-down also shows a per-type description when hovered.

---

### Opening the Exclusions Panel

1. Select a sync pair in the sidebar.
2. Click the pair's **Settings** button (⚙) and open the **Exclusions** tab.  
   The tab label shows the current rule count — e.g. **Exclusions (3)** — so you can see at a glance whether rules are active.

---

### Adding a Rule

Click **`+ Add`** in the button toolbar. A sheet appears where you can:

- Choose the **Type** from the drop-down. A live hint label below the picker explains the selected type with an example, updating as you switch types.
- Enter the **Pattern** (filename, path, or glob expression).
- Optionally add a **Note** — a short reminder for your own reference (e.g. "macOS metadata", "CI build output").

Click **Add** to save. The rule appears at the bottom of the list and takes effect on the next scan.

**Double-click** any rule in the list to edit it.

---

### Preset Templates

Click **Presets ▾** to insert a commonly-used exclusion pattern from a curated library, organised into groups:

| Group | Patterns included |
|---|---|
| **macOS** | `.DS_Store`, `.localized`, `.Spotlight-V100/`, `.Trashes/`, `.fseventsd/`, `__MACOSX/` |
| **Windows** | `Thumbs.db`, `desktop.ini`, `System Volume Information/` |
| **Temp & Build** | `*.tmp`, `*.log`, `*.bak`, `*.swp`, `.git/`, `node_modules/`, `__pycache__/`, `.cache/`, `.gradle/`, `build/`, `dist/`, `.next/` |
| **Office / Lock files** | `~$*` (Office lock files), `.~lock.*` (LibreOffice locks) |

Selecting a preset inserts it immediately with a pre-filled note. You can then edit the pattern if needed.

---

### Live Path Testing

The **Test path** bar sits between the rule list and the toolbar. Type any relative path (e.g. `docs/report.tmp` or `node_modules/lodash/index.js`) and Tandem instantly shows which rule — if any — would match it:

- **✓ "pattern" (Type)** in green — a specific rule matches this path.
- **✗ No rule matches** — the path would pass through to the diff engine.

The test result updates in real time as you type or as you modify rules.

---

### Reordering Rules

Drag any row by its left edge to reorder it. Tandem evaluates rules top-to-bottom, stopping at the first match; order can matter when patterns overlap. The new order is persisted to the database immediately.

---

### Bulk Enable / Disable (Context Menu)

Right-click anywhere on the rule list to access bulk operations:

| Action | Effect |
|---|---|
| **Enable All** | Enables every rule in the list. |
| **Disable All** | Disables every rule without deleting it. |
| **Toggle All** | Flips the enabled state of every rule individually. |
| **Enable Selected** | Enables only the highlighted rows. |
| **Disable Selected** | Disables only the highlighted rows. |

Disabling a rule suspends it without losing the pattern — useful for temporarily allowing a file through.

---

### Duplicating & Removing Rules

- **Duplicate** — Select a rule and click **Duplicate** to copy it (e.g. as the starting point for a similar pattern).
- **Remove** — Select one or more rules (hold ⌘ or ⇧ to multi-select) and click **Remove**. A confirmation prompt appears before deletion.

---

### Import & Export

You can save your rules to a JSON file and reload them later — or share them across machines or pairs.

- **Export…** — Opens a save panel. All current rules are written to a `.json` file (DB-internal fields like IDs are stripped; only type, pattern, enabled state, and note are saved).
- **Import…** — Opens an open panel. Rules from the file are appended after the existing rules; any rule already present is not deduplicated automatically.

The JSON format is a plain array of objects:

```json
[
  { "ruleType": "filename", "pattern": ".DS_Store", "isEnabled": true, "note": "macOS metadata" },
  { "ruleType": "glob",     "pattern": "*.tmp",      "isEnabled": true, "note": "" }
]
```

---

### Quick-Add from the Diff Tree

Right-click any file in the diff tree → **Add to Exclusions**. Tandem pre-fills a new rule with the file's relative path and opens the edit sheet so you can confirm or change the type before saving.

---

### Global Exclusions

Open **Tandem → Preferences… (⌘,)** and click the **Global Exclusions** tab. The interface is identical to pair-scoped rules. Global rules are applied in addition to any pair-level rules — both sets are merged before each scan.

---


## 10. Backup & History

### How Backups Work

Every time Tandem would overwrite or delete a file, it first moves the existing file to a **backup location** with a timestamp suffix:

```
~/Library/Application Support/Tandem/Backups/
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

Open **Tandem → Preferences** (⌘,).

| Setting | Description |
|---|---|
| **Auto-Sync on Detection** | In Real-Time mode, automatically sync immediately after a change is detected (no manual Sync click required). |
| **Show Same Files** | Whether to display unchanged files in the diff tree. |
| **Default Backup Location** | The base path used for backups when a pair hasn't specified its own. |
| **Debounce Interval** | How long (in seconds) to wait after a file-system event before triggering a scan (Real-Time mode). |
| **Launch at Login** | Register Tandem as a login item. |

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
xattr -cr /Applications/Tandem.app
```

Then try opening again.

### Scan Is Slow on Large Folders

Tandem computes SHA-256 checksums for every file to detect changes accurately. On first scan of a very large folder (e.g. hundreds of thousands of files), this may take several minutes. Subsequent scans are faster because only modified files are re-checksummed.

To speed things up:
- Add exclusion rules for `node_modules`, `.git`, `build` folders, or other large generated directories.
- Use **Scheduled** mode with a longer interval rather than **Real-Time** for very large trees.

### Permission Denied Errors

Tandem needs read/write access to both folders and the backup location. Check:

1. **System Settings → Privacy & Security → Files and Folders** — ensure Tandem has access.
2. The user account running Tandem owns or has write permissions for both folders.

### Files Re-Appear After Deletion

If a sync pair's mode is **bidirectional** and you delete a file on one side, Tandem may restore it from the other side. To permanently delete a file from both sides, first delete it from both Left and Right, then run a scan and sync (both sides will show it as absent, and the diff engine will leave it deleted).

### Clashes That Can't Be Resolved

If Quick Look shows blank previews (certain binary formats), use **Reveal in Finder** to open both versions in their native application, then choose **Use Left** or **Use Right** manually.

### Checking Logs

Tandem writes diagnostic messages to the macOS unified log. To view them:

```bash
log show --last 5m --predicate 'processImagePath CONTAINS[c] "tandem"' --style compact
```

Or open **Console.app** and filter for `Tandem`.

---

## 14. Privacy & Security

- Tandem does **not** connect to the internet. There are no analytics, telemetry, or cloud services.
- All data (sync pair configuration, tracked file records, backup history) is stored locally in an SQLite database at `~/Library/Application Support/Tandem/tandem.db`.
- Backup files are stored locally at the path you configure (default: `~/Library/Application Support/Tandem/Backups/`).
- File checksums (SHA-256) are stored in the database solely for change detection; they are never transmitted anywhere.

---

*For support, bug reports, or feature requests, please open an issue on [GitHub](https://github.com/saifgithub/Tandem/issues).*
