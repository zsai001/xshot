#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$ROOT_DIR/build/XShot.app"
PLIST_PATH="$ROOT_DIR/Resources/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")"
ARCH="$(uname -m)"
ARCHIVE_NAME="XShot-v${VERSION}-macos-${ARCH}.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
SHA_PATH="${ARCHIVE_PATH}.sha256"

# For public open-source distribution binaries, only use an explicit Developer ID certificate
# passed via XSHOT_SIGN_IDENTITY; otherwise default cleanly to ad-hoc signing ("-") so personal
# Apple Development certificates are never embedded into public releases.
export XSHOT_SIGN_IDENTITY="${XSHOT_SIGN_IDENTITY:--}"

echo "==> Building XShot v${VERSION} (${ARCH}) for release distribution..."
"$ROOT_DIR/scripts/build-app.sh"

echo "==> Verifying bundle signature..."
codesign --verify --deep --verbose=1 "$APP_BUNDLE"

echo "==> Packaging zero-DMG archive via macOS ditto..."
mkdir -p "$DIST_DIR"
rm -f "$ARCHIVE_PATH" "$SHA_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"

echo "==> Generating SHA-256 checksum..."
(cd "$DIST_DIR" && shasum -a 256 "$ARCHIVE_NAME" > "$(basename "$SHA_PATH")")

echo "✅ Release binary ready:"
echo "   Archive : $ARCHIVE_PATH ($(du -h "$ARCHIVE_PATH" | awk '{print $1}'))"
echo "   SHA-256 : $(cat "$SHA_PATH")"
