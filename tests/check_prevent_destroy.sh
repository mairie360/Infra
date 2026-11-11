#!/usr/bin/env bash
# Every `resource` block of the repository sets `prevent_destroy = true`
# (except the ACL / attachment resources listed below, which hold no data).
# A resource that must be deletable has to be added to ALLOWED, in review.
set -euo pipefail
cd "$(dirname "$0")/.."

ALLOWED='^(scaleway_object_bucket_acl)$'
status=0
while IFS= read -r file; do
  # Split the file into resource blocks: a block runs until the next
  # top-level `resource`, `data`, `module`, `output`, `variable` or `locals`.
  awk -v file="$file" -v allowed="$ALLOWED" '
    function flush() {
      if (type != "" && type !~ allowed && !guarded) {
        printf "%s:%d: resource %s.%s has no prevent_destroy = true\n", file, line, type, name
        bad = 1
      }
      type = ""
    }
    /^(resource|data|module|output|variable|locals|terraform|provider|import|moved)[ {]/ { flush() }
    /^resource "/ { gsub(/"/, ""); type = $2; name = $3; line = NR; guarded = 0 }
    /prevent_destroy[ ]*=[ ]*true/ { guarded = 1 }
    END { flush(); exit bad }
  ' "$file" || status=1
done < <(git ls-files --cached --others --exclude-standard '*.tf' 2>/dev/null || find . -name '*.tf' -not -path '*/.terraform/*')
exit $status
