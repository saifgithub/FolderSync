# FolderSync — Makefile
# All development stays in VSCode; this file is the only Xcode-less build interface.
#
# Targets:
#   make build    — swift build (debug)
#   make release  — swift build --release
#   make test     — swift test
#   make app      — assemble dist/FolderSync.app (debug, ad-hoc signed)
#   make app-rel  — assemble dist/FolderSync.app (release, ad-hoc signed)
#   make run      — build app then open it
#   make install  — copy .app to /Applications
#   make clean    — remove build artefacts and dist/

PRODUCT   := FolderSync
DIST      := dist
APP       := $(DIST)/$(PRODUCT).app
SCRIPT    := scripts/bundle.sh

# ── Build ─────────────────────────────────────────────────────────────────────
.PHONY: build
build:
	swift build

.PHONY: release
release:
	swift build -c release

# ── Test ──────────────────────────────────────────────────────────────────────
.PHONY: test
test:
	swift test

# ── Bundle .app ───────────────────────────────────────────────────────────────
.PHONY: app
app:
	@chmod +x $(SCRIPT)
	@$(SCRIPT) debug

.PHONY: app-rel
app-rel:
	@chmod +x $(SCRIPT)
	@$(SCRIPT) release

# ── Run ───────────────────────────────────────────────────────────────────────
.PHONY: run
run: app
	open "$(APP)"

.PHONY: run-release
run-release: app-rel
	open "$(APP)"

# ── Install to /Applications ──────────────────────────────────────────────────
.PHONY: install
install: app-rel
	@echo "Installing $(PRODUCT).app to /Applications…"
	cp -R "$(APP)" /Applications/
	@echo "✓ Installed /Applications/$(PRODUCT).app"

# ── Lint (requires swift-format) ──────────────────────────────────────────────
.PHONY: lint
lint:
	swift-format lint --recursive Sources/ Tests/

.PHONY: format
format:
	swift-format format --recursive --in-place Sources/ Tests/

# ── Clean ─────────────────────────────────────────────────────────────────────
.PHONY: clean
clean:
	swift package clean
	rm -rf $(DIST)
	@echo "✓ Cleaned"

# ── Resolve dependencies ──────────────────────────────────────────────────────
.PHONY: resolve
resolve:
	swift package resolve

# ── Print package graph ───────────────────────────────────────────────────────
.PHONY: deps
deps:
	swift package show-dependencies

# ── Default ───────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := build
