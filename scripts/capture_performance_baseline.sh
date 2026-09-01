#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 /absolute/path/to/CineLark.app [duration-seconds] [output.ndjson]" >&2
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
    usage
    exit 64
fi

app_bundle=$1
duration_seconds=${2:-60}
timestamp=$(/bin/date +%Y%m%d-%H%M%S)
output_path=${3:-"build/performance/cinelark-performance-${timestamp}.ndjson"}

if [[ "${app_bundle}" != /* || ! -d "${app_bundle}/Contents" ]]; then
    echo "error: app bundle must be an absolute path to a built .app" >&2
    exit 66
fi

if [[ ! "${duration_seconds}" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: duration must be a positive integer in seconds" >&2
    exit 64
fi

output_directory=$(/usr/bin/dirname "${output_path}")
/bin/mkdir -p "${output_directory}"

log_pid=""
cleanup() {
    if [[ -n "${log_pid}" ]] && /bin/kill -0 "${log_pid}" 2>/dev/null; then
        /bin/kill "${log_pid}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

/usr/bin/log stream \
    --style ndjson \
    --level info \
    --predicate 'subsystem == "com.samsonlab.cinelark" AND category == "Performance"' \
    --timeout "${duration_seconds}" \
    > "${output_path}" &
log_pid=$!

/usr/bin/open -na "${app_bundle}"
wait "${log_pid}"
log_pid=""

echo "Captured performance samples: ${output_path}"
echo "Summarize with: python3 scripts/summarize_performance_baseline.py \"${output_path}\""
