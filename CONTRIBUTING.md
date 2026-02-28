# Contributing to FolderSync

Thank you for your interest in contributing! This document explains how to get started.

---

## Code of Conduct

Be respectful and constructive. Everyone is welcome regardless of experience level.

---

## Getting Started

1. **Fork** the repository and clone your fork:

   ```bash
   git clone https://github.com/YOUR_USERNAME/FolderSync.git
   cd FolderSync
   ```

2. **Install build prerequisites:**
   - macOS 14.0+
   - Xcode Command Line Tools: `xcode-select --install`

3. **Build and run:**

   ```bash
   make app   # assembles dist/FolderSync.app
   make run   # builds and opens the app
   ```

4. **Run the tests:**

   ```bash
   make test
   ```

---

## Branching & Workflow

| Branch | Purpose |
|---|---|
| `main` | Stable, released code |
| `dev` | Integration branch for ongoing work |
| `feature/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `docs/<name>` | Documentation-only changes |

- Branch off `dev`, not `main`.
- Keep commits atomic and write meaningful commit messages (see below).
- Open a Pull Request against `dev` when your work is ready for review.

---

## Commit Message Style

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer]
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`

Examples:
```
feat(sync-engine): add progress reporting to FileScanner
fix(ui): prevent crash when removing last sync pair
docs(readme): add screenshot section
```

---

## Pull Request Checklist

- [ ] Compiles cleanly with no warnings (`make app-rel`)
- [ ] All existing tests pass (`make test`)
- [ ] New functionality is covered by tests where practical
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] PR description explains **what** changed and **why**

---

## Reporting Bugs

Use the [Bug Report](.github/ISSUE_TEMPLATE/bug_report.md) issue template. Include:
- macOS version and hardware (Apple Silicon / Intel)
- Steps to reproduce
- Expected vs. actual behaviour
- Console log output if available (`Console.app` → filter for "FolderSync")

---

## Suggesting Features

Use the [Feature Request](.github/ISSUE_TEMPLATE/feature_request.md) issue template. Explain the use-case before the solution.

---

## Code Style

- Follow standard Swift API Design Guidelines.
- Use `swift-format` (default settings) if available.
- Programmatic AppKit only — no Storyboards, no SwiftUI.
- All new UI must support both Light and Dark mode via semantic colours.
- Avoid force-unwrapping (`!`) except where the value is guaranteed at compile time.
