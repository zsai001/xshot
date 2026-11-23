#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/XShot.app"
BUNDLE_ID="top.xtags.xshot"
INSTALL_TO_APPS=false

if [[ "${1:-}" == "--install" ]]; then
  INSTALL_TO_APPS=true
fi

# Resolve signing identity safely without hardcoding personal certificates:
# 1. Explicit XSHOT_SIGN_IDENTITY env var
# 2. First available Developer ID Application / Apple Development identity in local Keychain
#    (preserves macOS Screen Recording / Accessibility TCC permissions across rebuilds)
# 3. Ad-hoc signing ("-") fallback for open-source contributors without an Apple Developer cert
SIGN_IDENTITY="${XSHOT_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E 'Developer ID Application:|Apple Development:' \
    | head -n 1 \
    | sed -E 's/.*"([^"]+)".*/\1/' || true)"
fi

echo "==> [1/4] Compiling XShot (Release, native macOS Swift)..."
cd "$ROOT_DIR"
swift build -c release

BIN_PATH="$ROOT_DIR/.build/release/XShot"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Error: compiled binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> [2/4] Generating native macOS AppIcon.icns..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> [3/4] Assembling XShot.app bundle..."
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/XShot"
chmod +x "$APP_BUNDLE/Contents/MacOS/XShot"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "==> [4/4] Signing XShot.app..."
if [[ "$SIGN_IDENTITY" != "-" ]] && [[ -n "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning | grep -Fq -- "$SIGN_IDENTITY"; then
  echo "    Using certificate: $SIGN_IDENTITY"
  codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
else
  echo "    Using ad-hoc signing (-)."
  codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
fi

echo "✅ Built: $APP_BUNDLE"

if [[ "$INSTALL_TO_APPS" == true ]]; then
  echo "==> Installing to /Applications/XShot.app..."
  rm -rf /Applications/XShot.app
  cp -R "$APP_BUNDLE" /Applications/XShot.app
  echo "✅ Installed: /Applications/XShot.app"
fi
