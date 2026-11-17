#!/usr/bin/env bash
# Push the alert rules of alerts/ to the Cockpit rulers of a group (MAIR-621).
#
#   scripts/push-alert-rules.sh <org>
#
# alerts/group/<ns>.yml goes to the group's probes data source,
# alerts/instance/<ns>.yml to every instance's metrics data source (__ENV__
# replaced by the env), each as namespace <ns> (one rule group per file).
# A namespace is replaced as a whole: re-running is idempotent. URLs come from
# the Terraform outputs; the ruler takes the IAM secret key (SCW_SECRET_KEY,
# ObservabilityFullAccess: the Apply workflow's key) as X-Auth-Token.
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "usage: $0 <org>" >&2
  exit 2
fi
org=$1
repo=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$repo/orgs/$org" ] || { echo "no such org: $org" >&2; exit 2; }
: "${SCW_SECRET_KEY:?SCW_SECRET_KEY (key with ObservabilityFullAccess) is required}"

push() { # <ruler base url> <namespace> <file> <label>
  local url="${1%/}/prometheus/config/v1/rules/$2"
  local code
  code=$(curl -sS -o /dev/stderr -w '%{http_code}' -X POST "$url" \
    -H "X-Auth-Token: $SCW_SECRET_KEY" -H 'Content-Type: application/yaml' \
    --data-binary @"$3")
  if [ "${code:0:1}" != 2 ]; then
    echo "$4: ruler answered $code for namespace $2" >&2
    exit 1
  fi
  echo "$4: namespace $2 pushed"
}

probes_url=$("$repo/scripts/tf.sh" "orgs/$org" output -json probes | jq -r .metrics_url)
for f in "$repo"/alerts/group/*.yml; do
  [ -e "$f" ] || continue
  push "$probes_url" "$(basename "$f" .yml)" "$f" "group $org"
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
"$repo/scripts/tf.sh" "orgs/$org" output -json instances \
  | jq -r 'to_entries[] | "\(.key) \(.value.cockpit_metrics_url)"' \
  | while read -r env url; do
      for f in "$repo"/alerts/instance/*.yml; do
        [ -e "$f" ] || continue
        sed "s/__ENV__/$env/g" "$f" > "$tmp"
        push "$url" "$(basename "$f" .yml)" "$tmp" "$org/$env"
      done
    done
