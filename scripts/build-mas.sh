#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAS_BUILD_DIR="$ROOT_DIR/build/mas"
ARCHIVE_PATH="$MAS_BUILD_DIR/XShot.xcarchive"
TEAM_ID="${XSHOT_DEVELOPMENT_TEAM:-}"
BUNDLE_ID="${XSHOT_BUNDLE_ID:-top.xtags.xshot}"
MODE="verify"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive)
      MODE="archive"
      shift
      ;;
    --team)
      TEAM_ID="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--archive] [--team <APPLE_TEAM_ID>] [--bundle-id <BUNDLE_ID>]" >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"

echo "==> [1/4] Generating Universal Mac App Store Xcode project..."
python3 "$ROOT_DIR/scripts/generate-mas-xcodeproj.py" --team "$TEAM_ID" --bundle-id "$BUNDLE_ID"

rm -rf "$MAS_BUILD_DIR"
mkdir -p "$MAS_BUILD_DIR"

if [[ "$MODE" == "archive" ]]; then
  if [[ -z "$TEAM_ID" ]]; then
    echo "Error: --archive requires --team <APPLE_TEAM_ID> (or XSHOT_DEVELOPMENT_TEAM env var)." >&2
    echo "Tip: Or open XShot.xcodeproj in Xcode, pick your Team under Signing & Capabilities, and click Product -> Archive." >&2
    exit 1
  fi
  echo "==> [2/4] Archiving Universal Mac App Store build (arm64 + x86_64)..."
  xcodebuild \
    -project "$ROOT_DIR/XShot.xcodeproj" \
    -scheme XShot \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive
  APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/XShot.app"
else
  echo "==> [2/4] Building Universal Mac App Store App Sandbox verification build (arm64 + x86_64)..."
  xcodebuild \
    -project "$ROOT_DIR/XShot.xcodeproj" \
    -scheme XShot \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$MAS_BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM="" \
    build
  APP_BUNDLE="$MAS_BUILD_DIR/DerivedData/Build/Products/Release/XShot.app"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Error: Built app bundle not found at $APP_BUNDLE" >&2
  exit 1
fi

echo "==> [3/4] Running 6-point Mac App Store compliance audit..."
BIN_PATH="$APP_BUNDLE/Contents/MacOS/XShot"
PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"

# 1. Universal architectures check
ARCH_INFO="$(lipo -info "$BIN_PATH")"
echo "    [1/6] Architectures: $ARCH_INFO"
if [[ "$ARCH_INFO" != *"arm64"* ]] || [[ "$ARCH_INFO" != *"x86_64"* ]]; then
  echo "Error: Expected Universal binary (arm64 + x86_64)" >&2
  exit 1
fi

# 2. Required Info.plist MAS keys
CAT="$(/usr/libexec/PlistBuddy -c 'Print :LSApplicationCategoryType' "$PLIST_PATH")"
ENC="$(/usr/libexec/PlistBuddy -c 'Print :ITSAppUsesNonExemptEncryption' "$PLIST_PATH")"
ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$PLIST_PATH")"
echo "    [2/6] Info.plist: Category=$CAT, NonExemptEncryption=$ENC, Icon=$ICON_NAME"
[[ "$ENC" == "false" ]] || { echo "Error: ITSAppUsesNonExemptEncryption must be false" >&2; exit 1; }

# 3. Compiled Asset Catalog + AppIcon check
if [[ ! -f "$APP_BUNDLE/Contents/Resources/Assets.car" ]] || [[ ! -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns" ]]; then
  echo "Error: Missing Assets.car or AppIcon.icns in bundle Resources" >&2
  exit 1
fi
echo "    [3/6] Asset catalog: Assets.car & AppIcon.icns verified"

# 4. App Sandbox entitlement check (and zero network entitlement)
ENTS="$(codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null)"
echo "$ENTS" | grep -Fq "com.apple.security.app-sandbox" || { echo "Error: Missing com.apple.security.app-sandbox entitlement!" >&2; exit 1; }
if echo "$ENTS" | grep -Fq "com.apple.security.network.client"; then
  echo "Warning: Network client entitlement is enabled in MAS build"
else
  echo "    [4/6] Entitlements: App Sandbox ON · 100% Offline (zero network entitlement)"
fi

# 5. Forbidden MAS API symbol audit
FORBIDDEN_SYMBOLS="_AXIsProcessTrusted|_AXUIElementCreateSystemWide|_CGPreflightListenEventAccess|_CGRequestListenEventAccess|_CGWarpMouseCursorPosition|_CGEventPost"
if nm -u "$BIN_PATH" | grep -Eq "$FORBIDDEN_SYMBOLS"; then
  echo "Error: Found MAS-restricted symbols in compiled binary:" >&2
  nm -u "$BIN_PATH" | grep -E "$FORBIDDEN_SYMBOLS" >&2
  exit 1
fi
echo "    [5/6] Binary symbol scan: 0 MAS-restricted Accessibility/CGEvent symbols"

# 6. Signature integrity
codesign --verify --deep --strict "$APP_BUNDLE"
echo "    [6/6] Code signature: valid on disk"

echo "==> [4/4] Mac App Store compliance audit PASSED!"
if [[ "$MODE" == "archive" ]]; then
  echo "✅ Archive ready for App Store Connect: $ARCHIVE_PATH"
  echo "   Open in Xcode Organizer: open \"$ARCHIVE_PATH\""
else
  echo "✅ Verified Universal MAS bundle: $APP_BUNDLE"
  echo "   Next: Open XShot.xcodeproj in Xcode, pick your Team, and click Product → Archive → Distribute App → App Store Connect"
fi
