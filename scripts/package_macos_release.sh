#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: package_macos_release.sh <exported-app-path> <version> <output-directory>

Validates an app exported by Xcode Automatic Signing and creates
CineLark_<version>_universal.dmg. This script never modifies code signatures.
EOF
}

if [[ $# -ne 3 ]]; then
  usage >&2
  exit 64
fi

APP_PATH=$1
VERSION=$2
OUTPUT_DIR=$3

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 66
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 65
fi

APP_EXECUTABLE="$APP_PATH/Contents/MacOS/CineLark"
BRIDGE_EXECUTABLE="$APP_PATH/Contents/Helpers/CineLarkBridge"
REMOTE_GATEWAY_EXECUTABLE="$APP_PATH/Contents/Helpers/CineLarkRemoteGateway"
PLUGIN_ARCHIVE="$APP_PATH/Contents/Resources/CineLark.iinaplgz"
APP_ICON="$APP_PATH/Contents/Resources/AppIcon.icns"
ASSET_CATALOG="$APP_PATH/Contents/Resources/Assets.car"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/B"
SIGNED_COMPONENTS=(
  "$APP_PATH"
  "$BRIDGE_EXECUTABLE"
  "$REMOTE_GATEWAY_EXECUTABLE"
  "$SPARKLE_FRAMEWORK"
  "$SPARKLE_VERSION_DIR/Updater.app"
  "$SPARKLE_VERSION_DIR/Autoupdate"
  "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
  "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
)

for required_path in \
  "$APP_EXECUTABLE" \
  "$BRIDGE_EXECUTABLE" \
  "$REMOTE_GATEWAY_EXECUTABLE" \
  "$PLUGIN_ARCHIVE" \
  "$APP_ICON" \
  "$ASSET_CATALOG" \
  "${SIGNED_COMPONENTS[@]}"; do
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

signature_value() {
  local path=$1
  local key=$2
  /usr/bin/codesign -dvv "$path" 2>&1 | \
    /usr/bin/awk -F= -v key="$key" '$1 == key && value == "" { value = $2 } END { print value }'
}

verify_universal "$APP_EXECUTABLE"
verify_universal "$BRIDGE_EXECUTABLE"
verify_universal "$REMOTE_GATEWAY_EXECUTABLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

HOST_TEAM=$(signature_value "$APP_PATH" TeamIdentifier)
HOST_AUTHORITY=$(signature_value "$APP_PATH" Authority)
if [[ -z "$HOST_TEAM" || "$HOST_TEAM" == "not set" ]]; then
  echo "The exported app has no Apple Team ID" >&2
  exit 65
fi
case "$HOST_AUTHORITY" in
  "Apple Development:"*|"Developer ID Application:"*) ;;
  *)
    echo "Unexpected Xcode signing authority: $HOST_AUTHORITY" >&2
    exit 65
    ;;
esac

for component in "${SIGNED_COMPONENTS[@]}"; do
  /usr/bin/codesign --verify --strict --verbose=2 "$component"
  component_team=$(signature_value "$component" TeamIdentifier)
  if [[ "$component_team" != "$HOST_TEAM" ]]; then
    echo "Signing Team mismatch: $component uses ${component_team:-no Team ID}, expected $HOST_TEAM" >&2
    exit 65
  fi
done

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
