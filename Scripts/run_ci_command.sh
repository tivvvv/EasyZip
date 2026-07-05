#!/usr/bin/env bash

set -uo pipefail

if [ "$#" -lt 2 ]; then
    echo "Usage: run_ci_command.sh <title> <command> [args...]"
    exit 2
fi

title="$1"
shift
output_file="$(mktemp)"

"$@" 2>&1 | tee "$output_file"
status="${PIPESTATUS[0]}"

if [ "$status" -ne 0 ]; then
    message="$(tail -40 "$output_file" | perl -0pe 's/%/%25/g; s/\r/%0D/g; s/\n/%0A/g')"
    printf '::error title=%s::%s\n' "$title" "$message"
fi

rm -f "$output_file"
exit "$status"
