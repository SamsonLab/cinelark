#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: package_macos_release.sh <app-path> <version> <output-directory> <signing-identity>

Signs a universal CineLark.app with the supplied Keychain identity and creates
CineLark_<version>_universal.dmg. The signing certificate may be self-signed;
Apple notarization is intentionally outside this script.
EOF
}

if [[ $# -ne 4 ]]; then
  usage >&2
  exit 64
fi

APP_PATH=$1
VERSION=$2
OUTPUT_DIR=$3
SIGNING_IDENTITY=$4

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 65
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "A signing identity is required" >&2
  exit 65
fi

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/CineLark"
BRIDGE_EXECUTABLE="$APP_PATH/Contents/Helpers/CineLarkBridge"
PLUGIN_ARCHIVE="$APP_PATH/Contents/Resources/CineLark.iinaplgz"
APP_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
ASSET_CATALOG="$APP_PATH/Contents/Resources/Assets.car"
for required_path in \
  "$APP_EXECUTABLE" \
  "$BRIDGE_EXECUTABLE" \
  "$PLUGIN_ARCHIVE" \
  "$APP_ICON" \
  "$ASSET_CATALOG"; do
  if [[ ! -e "$required_path" ]]; then
    echo "Release bundle is incomplete: $required_path" >&2
    exit 66
  fi
done

ICON_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$APP_PATH/Contents/Info.plist")
if [[ "$ICON_NAME" != "AppIcon" ]]; then
  echo "Release bundle does not reference the compiled AppIcon: $ICON_NAME" >&2
  exit 65
fi
if [[ -d "$APP_PATH/Contents/Resources/AppIcon.icon" ]]; then
  echo "Icon Composer source was copied instead of compiled; use Xcode 26 or later" >&2
  exit 65
fi

verify_universal() {
  local executable=$1
  if ! /usr/bin/lipo "$executable" -verify_arch arm64 x86_64; then
    echo "Release executable is not universal: $executable" >&2
    exit 65
  fi
}

sign_code() {
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp=none \
    "$1"
}

sign_code_preserving_entitlements() {
  /usr/bin/codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp=none \
    --preserve-metadata=entitlements \
    "$1"
}

verify_universal "$APP_EXECUTABLE"
verify_universal "$BRIDGE_EXECUTABLE"

# Sign from the innermost code outward so the app's resource seal contains the
# final signatures of every nested executable.
sign_code "$BRIDGE_EXECUTABLE"
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
  SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
    SPARKLE_INSTALLER="$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
    SPARKLE_DOWNLOADER="$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
    SPARKLE_AUTOUPDATE="$SPARKLE_VERSION_DIR/Autoupdate"
    SPARKLE_UPDATER="$SPARKLE_VERSION_DIR/Updater.app"
    for sparkle_component in \
      "$SPARKLE_INSTALLER" \
      "$SPARKLE_DOWNLOADER" \
      "$SPARKLE_AUTOUPDATE" \
      "$SPARKLE_UPDATER"; do
      if [[ ! -e "$sparkle_component" ]]; then
        echo "Sparkle bundle is incomplete: $sparkle_component" >&2
        exit 66
      fi
    done
    sign_code "$SPARKLE_INSTALLER"
    sign_code_preserving_entitlements "$SPARKLE_DOWNLOADER"
    sign_code "$SPARKLE_AUTOUPDATE"
    sign_code "$SPARKLE_UPDATER"
    sign_code "$SPARKLE_FRAMEWORK"
  fi

  while IFS= read -r -d '' nested_code; do
    if [[ "${SPARKLE_FRAMEWORK:-}" == "$nested_code" ]]; then
      continue
    fi
    sign_code "$nested_code"
  done < <(
    /usr/bin/find "$APP_PATH/Contents/Frameworks" -depth \
      \( -name '*.framework' -o -name '*.dylib' \) -print0
  )
fi
if [[ -d "$APP_PATH/Contents/PlugIns" ]]; then
  while IFS= read -r -d '' extension; do
    sign_code "$extension"
  done < <(/usr/bin/find "$APP_PATH/Contents/PlugIns" -depth -name '*.appex' -print0)
fi
sign_code "$APP_PATH"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")
if [[ "$bundle_version" != "$VERSION" ]]; then
  echo "Bundle version $bundle_version does not match release version $VERSION" >&2
  exit 65
fi
bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")
if [[ ! "$bundle_build" =~ ^[1-9][0-9]*$ ]]; then
  echo "Bundle build version must be a positive integer: $bundle_build" >&2
  exit 65
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
DMG_PATH="$OUTPUT_DIR/CineLark_${VERSION}_universal.dmg"
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cinelark-dmg.XXXXXX")
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/CineLark.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
/usr/bin/hdiutil create \
  -volname CineLark \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null

DIGEST=$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{ print $1 }')
/usr/bin/printf '%s  %s\n' "$DIGEST" "$(/usr/bin/basename "$DMG_PATH")" > "$DMG_PATH.sha256"
printf '%s\n' "$DMG_PATH"
