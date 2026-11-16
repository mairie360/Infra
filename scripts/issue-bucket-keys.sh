#!/usr/bin/env bash
# Issue the S3 key of each instance bucket into the vault (MAIR-619).
#
#   scripts/issue-bucket-keys.sh                  # every bucket without a key yet
#   scripts/issue-bucket-keys.sh prod/backup      # only these "<env>/<purpose>"
#   scripts/issue-bucket-keys.sh --rotate prod/elearning
#
# For each bucket of the `bucket_keys` output of iam/ (application, vault
# secret), creates an API key of the bucket's own IAM application and stores it
# as a new version of its vault secret (JSON access_key / secret_key), disabling
# the previous version. The key is never printed nor written to disk: role
# k8s_instance_secrets of mairie360/ansible reads it from the vault and seals
# it. A secret that already has an enabled version is skipped unless --rotate.
#
# After a rotation the old API keys still work: reseal the instance
# (ansible playbooks/secrets.yml), let Argo CD sync, then delete them with the
# `scw iam api-key delete` commands printed at the end.
#
# Needs the scw CLI with a key allowed to create API keys of applications
# (IAMManager, like `scripts/tf.sh iam apply`) and to write the vault.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
rotate=no
if [ "${1:-}" = --rotate ]; then
  rotate=yes
  shift
fi
if [ "$rotate" = yes ] && [ $# -eq 0 ]; then
  echo "--rotate needs the <env>/<purpose> to rotate (one at a time is safer)" >&2
  exit 2
fi

region=fr-par
project_id=$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' "$repo/iam/terraform.tfvars")
[ -n "$project_id" ] || { echo "no project_id in iam/terraform.tfvars" >&2; exit 1; }

keys_json=$("$repo/scripts/tf.sh" iam output -json bucket_keys)

if [ $# -eq 0 ]; then
  mapfile -t wanted < <(jq -r 'keys[]' <<<"$keys_json")
else
  wanted=("$@")
fi

cleanup=()
for k in "${wanted[@]}"; do
  entry=$(jq -c --arg k "$k" '.[$k] // empty' <<<"$keys_json")
  if [ -z "$entry" ]; then
    echo "$k: not in the bucket_keys output of iam/ (expected <env>/<purpose>)" >&2
    exit 1
  fi
  app=$(jq -r .application_id <<<"$entry")
  bucket=$(jq -r .name <<<"$entry")
  secret=$(jq -r .secret <<<"$entry")
  path=${secret%/*}
  name=${secret##*/}

  secret_id=$(scw secret secret list region="$region" project-id="$project_id" path="$path" name="$name" -o json | jq -r '.[0].id // empty')
  if [ -z "$secret_id" ]; then
    echo "$k: vault secret $secret missing: apply orgs/ first" >&2
    exit 1
  fi
  enabled=$(scw secret version list region="$region" secret-id="$secret_id" -o json | jq '[.[] | select(.status == "enabled")] | length')
  if [ "$enabled" -gt 0 ] && [ "$rotate" = no ]; then
    echo "$k: $secret already holds a key, skipped (--rotate to replace it)"
    continue
  fi

  old=$(scw iam api-key list application-id="$app" -o json | jq -r '.[].access_key')
  created=$(scw iam api-key create application-id="$app" default-project-id="$project_id" \
    description="S3 key of $bucket (mairie360/Infra scripts/issue-bucket-keys.sh)" -o json)
  jq -c '{access_key, secret_key}' <<<"$created" \
    | scw secret version create region="$region" secret-id="$secret_id" disable-previous=true \
        description="$(jq -r .access_key <<<"$created")" data=@/dev/stdin -o json >/dev/null
  echo "$k: new key $(jq -r .access_key <<<"$created") of $bucket stored in $secret"
  for ak in $old; do
    cleanup+=("scw iam api-key delete $ak   # previous key of $bucket")
  done
done

if [ ${#cleanup[@]} -gt 0 ]; then
  echo
  echo "Reseal the instances (ansible playbooks/secrets.yml), sync, then delete the previous keys:"
  printf '  %s\n' "${cleanup[@]}"
fi
