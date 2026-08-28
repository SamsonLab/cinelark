#!/bin/bash

set -euo pipefail

CONTAINER_ID="iCloud.com.samsonlab.cinelark"
EXPECTED_BUNDLE_ID="com.samsonlab.cinelark"
DEFAULT_SETTLE_SECONDS=30
CAPTURE_TIMEOUT_SECONDS=360

usage() {
  cat <<'EOF'
Usage:
  validate_cloudkit_sync.sh preflight /path/to/CineLark.app
  validate_cloudkit_sync.sh capture /path/to/CineLark.app /absolute/output.json
  validate_cloudkit_sync.sh compare /path/device-a.json /path/device-b.json

capture honors CINELARK_CLOUDKIT_AUDIT_SETTLE_SECONDS (0...300).
The app must not already be running, and capture never overwrites an output.
EOF
}

require_app() {
  local app_path="$1"
  if [[ ! -d "$app_path" || ! -x "$app_path/Contents/MacOS/CineLark" ]]; then
    echo "CineLark application is missing: $app_path" >&2
    exit 66
  fi
}

validate_audit() {
  local audit_path="$1"
  /usr/bin/python3 - "$audit_path" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    value = json.load(handle)

allowed_root = {
    "schemaVersion", "capturedAt", "syncPhase", "activeOperations",
    "lastSuccessfulSyncAt", "hasSyncFailure", "deviceCount",
    "profileSetDigest", "profiles",
}
allowed_profile = {
    "profileFingerprint", "favoriteStateCount", "playbackStateCount",
    "mediaSnapshotCount", "viewingSessionCount", "playbackEventCount",
    "latestMutationMillisecondsUTC", "factDigest",
}
if set(value) != allowed_root:
    raise SystemExit("Audit root contains missing or unexpected fields")
if value["schemaVersion"] != 1:
    raise SystemExit("Unsupported audit schema")
digest = re.compile(r"^[0-9a-f]{64}$")
if not digest.fullmatch(value["profileSetDigest"]):
    raise SystemExit("Invalid Profile-set digest")
for profile in value["profiles"]:
    if set(profile) != allowed_profile:
        raise SystemExit("Audit Profile contains missing or unexpected fields")
    if not digest.fullmatch(profile["profileFingerprint"]):
        raise SystemExit("Invalid Profile fingerprint")
    if not digest.fullmatch(profile["factDigest"]):
        raise SystemExit("Invalid fact digest")

print(
    f"Audit valid: phase={value['syncPhase']} "
    f"profiles={len(value['profiles'])} devices={value['deviceCount']}"
)
PY
}

preflight() (
  local app_path="$1"
  require_app "$app_path"
  /usr/bin/codesign --verify --deep --strict "$app_path"

  local work_dir
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinelark-cloudkit-preflight.XXXXXX")
  local entitlements_path="$work_dir/entitlements.plist"
  cleanup_preflight() {
    rm -rf "$work_dir"
  }
  trap cleanup_preflight EXIT

  /usr/bin/codesign -d --entitlements :- "$app_path" >"$entitlements_path"
  /usr/bin/python3 - "$entitlements_path" "$CONTAINER_ID" "$EXPECTED_BUNDLE_ID" <<'PY'
import plistlib
import sys

path, container_id, bundle_id = sys.argv[1:]
with open(path, "rb") as handle:
    entitlements = plistlib.load(handle)

if container_id not in entitlements.get(
    "com.apple.developer.icloud-container-identifiers", []
):
    raise SystemExit("Signed app is missing the expected iCloud container")
if "CloudKit" not in entitlements.get("com.apple.developer.icloud-services", []):
    raise SystemExit("Signed app is missing the CloudKit service entitlement")
team_id = entitlements.get("com.apple.developer.team-identifier")
application_id = entitlements.get("application-identifier")
if not team_id or application_id != f"{team_id}.{bundle_id}":
    raise SystemExit("Signed app identity does not match its Team and bundle ID")

print("Signed CloudKit preflight passed")
PY
)

capture() (
  local app_path="$1"
  local output_path="$2"
  require_app "$app_path"
  case "$output_path" in
    /*) ;;
    *) echo "Audit output must be an absolute path" >&2; exit 64 ;;
  esac
  if [[ -e "$output_path" ]]; then
    echo "Audit output already exists: $output_path" >&2
    exit 73
  fi
  if [[ ! -d "$(dirname "$output_path")" ]]; then
    echo "Audit output directory is missing: $(dirname "$output_path")" >&2
    exit 72
  fi
  if /usr/bin/pgrep -x CineLark >/dev/null; then
    echo "Quit every running CineLark instance before capturing an audit" >&2
    exit 75
  fi

  preflight "$app_path"
  local settle_seconds=${CINELARK_CLOUDKIT_AUDIT_SETTLE_SECONDS:-$DEFAULT_SETTLE_SECONDS}
  if [[ ! "$settle_seconds" =~ ^[0-9]+$ ]] || (( settle_seconds > 300 )); then
    echo "Settle seconds must be an integer from 0 through 300" >&2
    exit 64
  fi

  local work_dir
  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/cinelark-cloudkit-capture.XXXXXX")
  local capture_log="$work_dir/capture.log"
  cleanup_capture() {
    rm -rf "$work_dir"
  }
  trap cleanup_capture EXIT

  CINELARK_CLOUDKIT_AUDIT_OUTPUT="$output_path" \
  CINELARK_CLOUDKIT_AUDIT_SETTLE_SECONDS="$settle_seconds" \
    "$app_path/Contents/MacOS/CineLark" >"$capture_log" 2>&1 &
  local app_pid=$!
  local elapsed=0
  while /bin/kill -0 "$app_pid" 2>/dev/null; do
    if (( elapsed >= CAPTURE_TIMEOUT_SECONDS )); then
      /bin/kill -TERM "$app_pid" 2>/dev/null || true
      wait "$app_pid" 2>/dev/null || true
      echo "CloudKit audit capture timed out" >&2
      exit 70
    fi
    /bin/sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$app_pid" 2>/dev/null || true

  if [[ ! -f "$output_path" ]]; then
    echo "CloudKit audit capture failed without producing output" >&2
    exit 70
  fi
  validate_audit "$output_path"
)

compare() {
  local first_path="$1"
  local second_path="$2"
  validate_audit "$first_path"
  validate_audit "$second_path"
  /usr/bin/python3 - "$first_path" "$second_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    first = json.load(handle)
with open(sys.argv[2], "r", encoding="utf-8") as handle:
    second = json.load(handle)

for name, value in (("first", first), ("second", second)):
    if value["syncPhase"] != "upToDate":
        raise SystemExit(f"{name} replica is not up to date")
    if value["hasSyncFailure"] or value["activeOperations"]:
        raise SystemExit(f"{name} replica still has active or failed transport state")

if first["profileSetDigest"] != second["profileSetDigest"]:
    raise SystemExit("Profile datasets have not converged")
if first["profiles"] != second["profiles"]:
    raise SystemExit("Per-Profile fact families have not converged")
if first["deviceCount"] != second["deviceCount"]:
    raise SystemExit("Device-record counts have not converged")

print(
    f"Replica convergence passed: profiles={len(first['profiles'])} "
    f"devices={first['deviceCount']}"
)
PY
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

case "$1" in
  preflight)
    [[ $# -eq 2 ]] || { usage >&2; exit 64; }
    preflight "$2"
    ;;
  capture)
    [[ $# -eq 3 ]] || { usage >&2; exit 64; }
    capture "$2" "$3"
    ;;
  compare)
    [[ $# -eq 3 ]] || { usage >&2; exit 64; }
    compare "$2" "$3"
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
