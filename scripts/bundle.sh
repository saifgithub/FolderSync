#!/usr/bin/env bash
# bundle.sh — Assembles FolderSync.app from the SPM build output.
#
# Usage:
#   ./scripts/bundle.sh [debug|release]       default: debug
#
# The script:
#   1. Picks the right SPM binary (debug / release)
#   2. Creates the .app bundle directory structure
#   3. Copies the binary + Info.plist + entitlements
#   4. Ad-hoc signs the bundle (no Apple Developer account required)
#   5. Prints the path to the finished .app
#
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
PRODUCT_NAME="FolderSync"
BUNDLE_ID="com.foldersync.app"
CONFIG="${1:-debug}"                          # debug | release
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIG"
RESOURCES_DIR="$ROOT_DIR/Resources"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"

# ── Banner ────────────────────────────────────────────────────────────────────
echo "▶ Bundling $PRODUCT_NAME ($CONFIG)"

# ── 1. Build (skip if binary already up to date) ──────────────────────────────
if [[ "$CONFIG" == "release" ]]; then
    echo "  Building release…"
    (cd "$ROOT_DIR" && swift build -c release 2>&1)
else
    echo "  Building debug…"
    (cd "$ROOT_DIR" && swift build 2>&1)
fi

BINARY="$BUILD_DIR/$PRODUCT_NAME"

if [[ ! -f "$BINARY" ]]; then
    echo "✗ Binary not found at $BINARY" >&2
    exit 1
fi

# ── 2. Create .app directory structure ────────────────────────────────────────
echo "  Assembling .app bundle…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ── 3. Copy binary ────────────────────────────────────────────────────────────
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$PRODUCT_NAME"

# ── 4. Copy Info.plist ────────────────────────────────────────────────────────
if [[ ! -f "$RESOURCES_DIR/Info.plist" ]]; then
    echo "✗ Resources/Info.plist not found" >&2
    exit 1
fi
cp "$RESOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# ── 5. Copy app icon if it exists ─────────────────────────────────────────────
if [[ -f "$RESOURCES_DIR/AppIcon.icns" ]]; then
    cp "$RESOURCES_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    # Tell the plist about it
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" \
        "$APP_BUNDLE/Contents/Info.plist"
fi

# ── 6. Inject version from git tag (optional, never fails) ───────────────────
GIT_TAG=$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
GIT_COMMIT=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "0")
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GIT_TAG" \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GIT_COMMIT" \
    "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true

# ── 7. Ad-hoc code sign ───────────────────────────────────────────────────────
# "-" means ad-hoc (no Developer ID required).
# Add "--entitlements" so macOS respects the declared permissions.
echo "  Signing (ad-hoc)…"
codesign \
    --force \
    --deep \
    --sign "-" \
    --entitlements "$RESOURCES_DIR/FolderSync.entitlements" \
    --options runtime \
    "$APP_BUNDLE"

# ── 8. Verify ─────────────────────────────────────────────────────────────────
codesign --verify --deep --strict "$APP_BUNDLE" && \
    echo "  Signature: ✓"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Built: $APP_BUNDLE"
echo ""
echo "  Run it:          open \"$APP_BUNDLE\""
echo "  Install to /Applications:"
echo "    cp -R \"$APP_BUNDLE\" /Applications/"
