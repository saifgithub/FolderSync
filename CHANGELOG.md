# Changelog

All notable changes to Tandem are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- Public GitHub repository with MIT license
- Signed & notarised DMG distribution workflow (`scripts/sign_and_dmg.sh`)

---

## [1.0.0] — 2026-02-28

### Added
- Initial release of Tandem
- Multiple sync pair management via sidebar
- Side-by-side diff tree (`NSOutlineView`) showing New, Updated, Deleted, Same, Clash states
- Manual, Real-Time (FSEvents), and Scheduled sync modes
- SHA-256 based diff engine for accurate change detection
- Conflict (Clash) resolution with Quick Look file preview
- Exclusion rules: filename, relative path, folder name, glob patterns (`fnmatch`)
- Secure backup: replaced/deleted files moved to timestamped backup folder
- Right-click context menus: Sync File, Force Copy, Resolve Clash, Add to Exclusions, Reveal in Finder
- Backup history viewer
- App preferences window
- GRDB.swift SQLite persistence for sync pairs, tracked files, backup records, and exclusion rules
- Native AppKit programmatic UI (no Storyboards / XIBs)
- Swift Package Manager project structure with `TandemCore` library and `Tandem` executable targets
- Makefile build system (`build`, `release`, `app`, `app-rel`, `run`, `test`, `install`, `clean`)
- Ad-hoc code signing via `scripts/bundle.sh`

---

[Unreleased]: https://github.com/saifgithub/Tandem/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/saifgithub/Tandem/releases/tag/v1.0.0
