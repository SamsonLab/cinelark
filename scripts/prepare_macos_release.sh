#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: prepare_macos_release.sh [output-directory]

Archives and exports CineLark with local Xcode Automatic Signing, performs a
launch smoke test, packages the universal DMG, and signs the Sparkle appcast
with the maintainer Keychain key.
EOF
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT_FILE="$ROOT_DIR/apps/macos/project.yml"
PROJECT_PATH="$ROOT_DIR/apps/macos/CineLark.xcodeproj"
EXPORT_OPTIONS="$ROOT_DIR/apps/macos/Config/ExportOptions.plist"
OUTPUT_DIR=${1:-"$ROOT_DIR/build/release"}
SPARKLE_KEY_ACCOUNT=${SPARKLE_KEY_ACCOUNT:-com.samsonlab.cinelark}

VERSION=$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_FILE")
BUILD_VERSION=$(awk '/CURRENT_PROJECT_VERSION:/ { print $2; exit }' "$PROJECT_FILE")
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid MARKETING_VERSION: $VERSION" >&2
  exit 65
fi
if [[ ! "$BUILD_VERSION" =~ ^[1-9][0-9]*$ ]]; then
  echo "CURRENT_PROJECT_VERSION must be a positive integer: $BUILD_VERSION" >&2
  exit 65
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cinelark-release.XXXXXX")
ARCHIVE_PATH="$WORK_DIR/CineLark.xcarchive"
DERIVED_DATA="$WORK_DIR/DerivedData"
EXPORT_DIR="$WORK_DIR/export"
ARTIFACT_DIR="$WORK_DIR/artifacts"
LAUNCH_LOG="$WORK_DIR/launch.log"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$ARTIFACT_DIR" "$OUTPUT_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme CineLark \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

APP_PATH="$EXPORT_DIR/CineLark.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/CineLark"
if [[ ! -x "$APP_EXECUTABLE" ]]; then
  echo "Exported application is missing: $APP_PATH" >&2
  exit 66
fi

LLVM_PROFILE_FILE="$WORK_DIR/cinelark-%p.profraw" "$APP_EXECUTABLE" >"$LAUNCH_LOG" 2>&1 &
APP_PID=$!
sleep 5
if ! kill -0 "$APP_PID" 2>/dev/null; then
  wait "$APP_PID" || true
  echo "Exported application terminated during launch smoke test:" >&2
  cat "$LAUNCH_LOG" >&2
  exit 70
fi
kill -TERM "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

"$SCRIPT_DIR/package_macos_release.sh" "$APP_PATH" "$VERSION" "$ARTIFACT_DIR" >/dev/null

GENERATE_APPCAST=$(find "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin" \
  -maxdepth 1 -name generate_appcast -type f -perm +111 -print -quit)
SIGN_UPDATE=$(find "$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin" \
  -maxdepth 1 -name sign_update -type f -perm +111 -print -quit)
if [[ -z "$GENERATE_APPCAST" || -z "$SIGN_UPDATE" ]]; then
  echo "Sparkle release tools are unavailable" >&2
  exit 69
fi

DMG_BASENAME="CineLark_${VERSION}_universal"
RELEASE_NOTES="$ARTIFACT_DIR/$DMG_BASENAME.md"
cat > "$RELEASE_NOTES" <<EOF
CineLark $VERSION for macOS 26 or later.

## Highlights

- Introduced the new CineLark lark icon and matching in-app brand mark.
- Fixed secure Remote gateway startup when paired devices already exist,
  restoring QR-code pairing without clearing saved credentials.
- Hardened managed IINA player teardown by cancelling plugin timers before IINA
  releases its API owner, preventing an application-termination crash.

## Install

\`\`\`sh
brew install --cask samsonlab/cinelark/cinelark
\`\`\`

CineLark is exported locally with Xcode Automatic Signing and is not currently
Developer ID notarized. The Homebrew Cask pins this artifact by SHA-256 and
removes quarantine after installation. In-app updates are authenticated
independently with Sparkle EdDSA signatures.
EOF

"$GENERATE_APPCAST" \
  --account "$SPARKLE_KEY_ACCOUNT" \
  --download-url-prefix "https://github.com/SamsonLab/cinelark/releases/download/v${VERSION}/" \
  --link "https://github.com/SamsonLab/cinelark" \
  --embed-release-notes \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  -o "$ARTIFACT_DIR/appcast.xml" \
  "$ARTIFACT_DIR"

APPCAST_PATH="$ARTIFACT_DIR/appcast.xml"
if ! grep -Fq "CineLark_${VERSION}_universal.dmg" "$APPCAST_PATH"; then
  echo "Sparkle appcast does not reference the release DMG" >&2
  exit 65
fi
if ! grep -Fq "<sparkle:version>${BUILD_VERSION}</sparkle:version>" "$APPCAST_PATH"; then
  echo "Sparkle appcast does not contain build $BUILD_VERSION" >&2
  exit 65
fi
if ! grep -Fq "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" "$APPCAST_PATH"; then
  echo "Sparkle appcast does not contain version $VERSION" >&2
  exit 65
fi
if ! grep -Fq "sparkle:edSignature" "$APPCAST_PATH" || \
   ! grep -Fq "<!-- sparkle-signatures:" "$APPCAST_PATH"; then
  echo "Sparkle archive or appcast signature is missing" >&2
  exit 65
fi
"$SIGN_UPDATE" --account "$SPARKLE_KEY_ACCOUNT" --verify "$APPCAST_PATH"

cp "$RELEASE_NOTES" "$ARTIFACT_DIR/release-notes.md"
rm -f \
  "$OUTPUT_DIR/CineLark_${VERSION}_universal.dmg" \
  "$OUTPUT_DIR/CineLark_${VERSION}_universal.dmg.sha256" \
  "$OUTPUT_DIR/CineLark_${VERSION}_universal.md" \
  "$OUTPUT_DIR/appcast.xml" \
  "$OUTPUT_DIR/release-notes.md"
cp \
  "$ARTIFACT_DIR/CineLark_${VERSION}_universal.dmg" \
  "$ARTIFACT_DIR/CineLark_${VERSION}_universal.dmg.sha256" \
  "$ARTIFACT_DIR/CineLark_${VERSION}_universal.md" \
  "$ARTIFACT_DIR/appcast.xml" \
  "$ARTIFACT_DIR/release-notes.md" \
  "$OUTPUT_DIR/"

printf 'Prepared CineLark %s (%s) at %s\n' "$VERSION" "$BUILD_VERSION" "$(cd "$OUTPUT_DIR" && pwd)"
