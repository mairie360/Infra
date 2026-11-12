#!/usr/bin/env bash
# Create the Terraform state bucket once, then keep bootstrap/'s own state in it.
#
#   scripts/bootstrap.sh
#
# The bucket cannot hold the state that creates it, so the first apply uses a
# local backend (a git-ignored *_override.tf), then the state is moved into the
# bucket and the local copy deleted, only once the bucket holds it.
#
# Every run picks up where the previous one stopped:
#   - no bucket, or a local state left -> local apply, then migration. A run
#     behind (a stopped run)              stopped after creating the bucket may
#                                         lack the rest (the ACL): the apply
#                                         against the local state finishes it;
#   - bucket, no local state           -> plan of bootstrap/ against its own state.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=$repo/bootstrap
tf=$repo/scripts/tf.sh
bucket=mairie360-tfstate
override=$root/backend_override.tf
local_state=$root/terraform.tfstate

# Moves the local state into the bucket, then deletes the local copy once
# terraform reads the resources back from the bucket.
migrate() {
  rm -f "$override"
  "$tf" bootstrap init -input=false -migrate-state -force-copy
  if [ -z "$("$tf" bootstrap state list)" ]; then
    echo "the bucket state of bootstrap/ is empty after the migration: $local_state is kept" >&2
    exit 1
  fi
  rm -f "$local_state" "$local_state.backup"
  echo "bootstrap/ state is now in s3://$bucket/bootstrap.tfstate."
}

if [ ! -s "$local_state" ] && scw object bucket get "$bucket" region=fr-par >/dev/null 2>&1; then
  echo "$bucket exists: planning bootstrap/ against its own state."
  exec "$tf" bootstrap plan
fi
if [ -s "$local_state" ]; then
  echo "bootstrap/ still has a local state: applying what a stopped run left, then migrating."
fi

# The override only lives for the local apply (removed even when it fails);
# the migration removes it too.
trap 'rm -f "$override"' EXIT
cat > "$override" <<'HCL'
terraform {
  backend "local" {}
}
HCL

"$tf" bootstrap init -input=false -reconfigure
"$tf" bootstrap apply
migrate
