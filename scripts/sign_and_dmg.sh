#!/usr/bin/env bash
# sign_and_dmg.sh — Sign Tandem.app and package it into a DMG.
#
# ─────────────────────────────────────────────────────────────────────────────
# USAGE
#   ./scripts/sign_and_dmg.sh [debug|release]
#
#   Without environment variables the script performs AD-HOC signing only and
#   skips notarisation — suitable for local testing or open-source distribution.
#
#   For a fully signed & notarised release, export the following before running:
#
#     export CERT="Developer ID Application: Your Name (TEAMID)"
#     export APPLE_ID="you@example.com"
#     export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"   # App-specific password
#     export TEAM_ID="YOURTEAMID"
#
# REQUIREMENTS
#   • Xcode Command Line Tools (codesign, hdiutil, xcrun)
#   • create-dmg (optional but recommended): brew install create-dmg
#     Falls back to hdiutil if create-dmg is not installed.
#
# OUTPUT
#   dist/Tandem-<version>.dmg
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

PRODUCT_NAME="Tandem"
CONFIG="${1:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"

# ── Signing identity ─────────────────────────────────────────────────────────
CERT="${CERT:-}"          # e.g. "Developer ID Application: Your Name (TEAMID)"
APPLE_ID="${APPLE_ID:-}"  # Apple ID for notarisation
APP_PASSWORD="${APP_PASSWORD:-}"
TEAM_ID="${TEAM_ID:-}"

# ── Step 1: Build the .app bundle ────────────────────────────────────────────
echo "▶ Building $PRODUCT_NAME ($CONFIG)…"
chmod +x "$SCRIPT_DIR/bundle.sh"
"$SCRIPT_DIR/bundle.sh" "$CONFIG"

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "✗ App bundle not found at $APP_BUNDLE" >&2
    exit 1
fi

# ── Step 2: Determine version string ─────────────────────────────────────────
VERSION=$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
DMG_NAME="${PRODUCT_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "  Version: $VERSION"

# ── Step 3: Code Sign ────────────────────────────────────────────────────────
if [[ -n "$CERT" ]]; then
    echo "▶ Signing with certificate: $CERT"
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ROOT_DIR/Resources/Tandem.entitlements" \
        --sign "$CERT" \
        "$APP_BUNDLE"
    echo "  ✓ Signed (Developer ID)"
else
    echo "▶ Signing ad-hoc (no CERT set)"
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "  ✓ Signed (ad-hoc)"
fi

# ── Step 4: Verify signature ─────────────────────────────────────────────────
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE" 2>&1 || {
    echo "✗ Codesign verification failed" >&2; exit 1
}

# ── Step 5: Create DMG ───────────────────────────────────────────────────────
rm -f "$DMG_PATH"

if command -v create-dmg &>/dev/null; then
    echo "▶ Creating DMG with create-dmg…"
    create-dmg \
        --volname "$PRODUCT_NAME $VERSION" \
        --volicon "$ROOT_DIR/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "$PRODUCT_NAME.app" 150 180 \
        --hide-extension "$PRODUCT_NAME.app" \
        --app-drop-link 450 180 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$APP_BUNDLE" || {
            echo "  create-dmg failed, falling back to hdiutil…"
            _build_hdiutil_dmg
        }
else
    echo "▶ create-dmg not found — using hdiutil (install with: brew install create-dmg)"
    _build_hdiutil_dmg() {
        STAGING="$DIST_DIR/.dmg_staging"
        rm -rf "$STAGING"
        mkdir -p "$STAGING"
        cp -R "$APP_BUNDLE" "$STAGING/"
        ln -s /Applications "$STAGING/Applications"
        hdiutil create \
            -volname "$PRODUCT_NAME $VERSION" \
            -srcfolder "$STAGING" \
            -ov -format UDZO \
            "$DMG_PATH"
        rm -rf "$STAGING"
    }
    _build_hdiutil_dmg
fi

echo "  ✓ DMG created: $DMG_PATH"

# ── Step 6: Sign the DMG ─────────────────────────────────────────────────────
if [[ -n "$CERT" ]]; then
    codesign --force --sign "$CERT" "$DMG_PATH"
    echo "  ✓ DMG signed"
fi

# ── Step 7: Notarise (optional) ──────────────────────────────────────────────
if [[ -n "$CERT" && -n "$APPLE_ID" && -n "$APP_PASSWORD" && -n "$TEAM_ID" ]]; then
    echo "▶ Submitting for notarisation (this may take a few minutes)…"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APP_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    echo "▶ Stapling notarisation ticket…"
    xcrun stapler staple "$DMG_PATH"
    echo "  ✓ Notarised and stapled"
else
    echo "  (Notarisation skipped — set CERT, APPLE_ID, APP_PASSWORD, TEAM_ID to enable)"
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "✓ Done: $DMG_PATH"
ls -lh "$DMG_PATH"
