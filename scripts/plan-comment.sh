#!/usr/bin/env bash
# Markdown of a terraform plan, for a pull request comment or a job summary (MAIR-803).
#
#   scripts/plan-comment.sh <root> <plan output file> <terraform exit code>
#
# Exit code of `plan -detailed-exitcode`: 0 no change, 2 changes, other = error.
# The output is cut to stay under GitHub's 65536-character comment limit.
set -euo pipefail

if [ $# -ne 3 ]; then
  echo "usage: $0 <root> <plan output> <exit code>" >&2
  exit 2
fi
root=$1
file=$2
code=$3
max=60000

case "$code" in
  0) status="no change" ;;
  2) status="changes: $(grep -E '^Plan: ' "$file" | tail -1 || true)" ;;
  *) status="**error** (exit code $code)" ;;
esac

echo "### terraform plan \`$root\`: $status"
echo
echo "<details><summary>Output</summary>"
echo
echo '```'
if [ "$(wc -c < "$file")" -gt "$max" ]; then
  tail -c "$max" "$file"
  echo
  echo "[... beginning cut: see the job log for the full plan]"
else
  cat "$file"
fi
echo '```'
echo
echo "</details>"
