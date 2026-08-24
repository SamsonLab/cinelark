#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: publish_macos_release.sh <artifact-directory>

Publishes the locally signed release artifacts for the version at HEAD and
updates SamsonLab/homebrew-cinelark. The matching tag must already point to HEAD.
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 64
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PROJECT_FILE="$ROOT_DIR/apps/macos/project.yml"
ARTIFACT_DIR=$(cd "$1" && pwd)
VERSION=$(awk '/MARKETING_VERSION:/ { print $2; exit }' "$PROJECT_FILE")
TAG="v$VERSION"
DMG_PATH="$ARTIFACT_DIR/CineLark_${VERSION}_universal.dmg"
SHA_PATH="$DMG_PATH.sha256"
APPCAST_PATH="$ARTIFACT_DIR/appcast.xml"
RELEASE_NOTES="$ARTIFACT_DIR/release-notes.md"

if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
  echo "Repository must be clean before publishing" >&2
  exit 65
fi
if ! git -C "$ROOT_DIR" rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Missing release tag: $TAG" >&2
  exit 65
fi
if [[ "$(git -C "$ROOT_DIR" rev-list -n 1 "$TAG")" != "$(git -C "$ROOT_DIR" rev-parse HEAD)" ]]; then
  echo "Tag $TAG does not point to HEAD" >&2
  exit 65
fi
for artifact in "$DMG_PATH" "$SHA_PATH" "$APPCAST_PATH" "$RELEASE_NOTES"; do
  if [[ ! -s "$artifact" ]]; then
    echo "Release artifact is missing: $artifact" >&2
    exit 66
  fi
done

(cd "$ARTIFACT_DIR" && /usr/bin/shasum -a 256 -c "$(basename "$SHA_PATH")")
SHA256=$(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{ print $1 }')
if ! grep -Fq "CineLark_${VERSION}_universal.dmg" "$APPCAST_PATH"; then
  echo "Appcast does not match $TAG" >&2
  exit 65
fi

if gh release view "$TAG" --repo SamsonLab/cinelark >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG_PATH" "$SHA_PATH" "$APPCAST_PATH" \
    --clobber \
    --repo SamsonLab/cinelark
else
  gh release create "$TAG" "$DMG_PATH" "$SHA_PATH" "$APPCAST_PATH" \
    --title "CineLark $TAG" \
    --notes-file "$RELEASE_NOTES" \
    --repo SamsonLab/cinelark
fi

TAP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/homebrew-cinelark.XXXXXX")
cleanup() {
  rm -rf "$TAP_DIR"
}
trap cleanup EXIT
gh repo clone SamsonLab/homebrew-cinelark "$TAP_DIR"
CASK_PATH="$TAP_DIR/Casks/cinelark.rb"
if [[ ! -f "$CASK_PATH" ]]; then
  echo "Homebrew Cask is missing: $CASK_PATH" >&2
  exit 66
fi
/usr/bin/sed -i '' -E "s/^  version \"[^\"]+\"/  version \"$VERSION\"/" "$CASK_PATH"
/usr/bin/sed -i '' -E "s/^  sha256 \"[0-9a-f]+\"/  sha256 \"$SHA256\"/" "$CASK_PATH"

git -C "$TAP_DIR" config user.name "SamsonLab Release"
git -C "$TAP_DIR" config user.email "release@samsonlab.com"
git -C "$TAP_DIR" add Casks/cinelark.rb
if ! git -C "$TAP_DIR" diff --cached --quiet; then
  git -C "$TAP_DIR" commit -m "Update cask to $TAG"
  git -C "$TAP_DIR" push origin main
fi

printf 'Published CineLark %s and updated Homebrew Cask\n' "$VERSION"
