#!/usr/bin/env bash
# Issue the Cockpit token of each instance into the vault (MAIR-620).
#
#   scripts/issue-cockpit-tokens.sh <org>                 # every env without a token yet
#   scripts/issue-cockpit-tokens.sh <org> prod            # only these envs
#   scripts/issue-cockpit-tokens.sh --rotate <org> prod
#
# Creates a Cockpit token limited to pushing metrics and traces
# (write_only_metrics, write_only_traces) named <org>-<env>-collector, and
# stores its secret key as a new version of /<org>/<env>/cockpit-token,
# disabling the previous one. Never printed nor written to disk, never in the
# Terraform state: role k8s_instance_secrets of mairie360/ansible reads it from
# the vault and seals it as COCKPIT_TOKEN of the instance's collector. A secret
# that already has an enabled version is skipped unless --rotate; after a
# rotation, reseal, sync, then delete the previous token with the printed
# command.
set -euo pipefail

rotate=no
if [ "${1:-}" = --rotate ]; then
  rotate=yes
  shift
fi
if [ $# -lt 1 ]; then
  echo "usage: $0 [--rotate] <org> [env...]" >&2
  exit 2
fi
org=$1
shift
if [ "$rotate" = yes ] && [ $# -eq 0 ]; then
  echo "--rotate needs the env to rotate" >&2
  exit 2
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
region=fr-par
tfvars="$repo/orgs/$org/terraform.tfvars"
[ -f "$tfvars" ] || { echo "no such org: $org" >&2; exit 2; }
project_id=$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' "$tfvars")
if [ $# -eq 0 ]; then
  mapfile -t envs < <("$repo/scripts/tf.sh" "orgs/$org" output -json instances | jq -r 'keys[]')
else
  envs=("$@")
fi

cleanup=()
for env in "${envs[@]}"; do
  name="$org-$env-collector"
  secret_id=$(scw secret secret list region="$region" project-id="$project_id" path="/$org/$env" name=cockpit-token -o json | jq -r '.[0].id // empty')
  if [ -z "$secret_id" ]; then
    echo "$env: vault secret /$org/$env/cockpit-token missing: apply orgs/$org first" >&2
    exit 1
  fi
  enabled=$(scw secret version list region="$region" secret-id="$secret_id" -o json | jq '[.[] | select(.status == "enabled")] | length')
  if [ "$enabled" -gt 0 ] && [ "$rotate" = no ]; then
    echo "$env: /$org/$env/cockpit-token already holds a token, skipped (--rotate to replace it)"
    continue
  fi
  old=$(scw cockpit token list region="$region" project-id="$project_id" -o json | jq -r --arg n "$name" '.[] | select(.name == $n) | .id')
  created=$(scw cockpit token create region="$region" project-id="$project_id" name="$name" \
    token-scopes.0=write_only_metrics token-scopes.1=write_only_traces -o json)
  jq -j '.secret_key' <<<"$created" \
    | scw secret version create region="$region" secret-id="$secret_id" disable-previous=true \
        description="cockpit token $(jq -r .id <<<"$created")" data=@/dev/stdin -o json >/dev/null
  echo "$env: new Cockpit token $(jq -r .id <<<"$created") stored in /$org/$env/cockpit-token"
  for id in $old; do
    cleanup+=("scw cockpit token delete region=$region token-id=$id   # previous token of $env")
  done
done

if [ ${#cleanup[@]} -gt 0 ]; then
  echo
  echo "Reseal the instances (ansible playbooks/secrets.yml), sync, then delete the previous tokens:"
  printf '  %s\n' "${cleanup[@]}"
fi
