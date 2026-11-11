#!/usr/bin/env bash
# Create the Terraform state bucket once, then keep bootstrap/'s own state in it.
#
#   scripts/bootstrap.sh
#
# The bucket cannot hold the state that creates it, so the first apply uses a
# local backend (a git-ignored *_override.tf), then the state is moved into the
# bucket and the local copy deleted. Once the bucket exists the script only
# runs a normal plan of bootstrap/.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
root=$repo/bootstrap
tf=$repo/scripts/tf.sh

if scw object bucket get mairie360-tfstate region=fr-par >/dev/null 2>&1; then
  echo "mairie360-tfstate exists: planning bootstrap/ against its own state."
  exec "$tf" bootstrap plan
fi

override=$root/backend_override.tf
trap 'rm -f "$override"' EXIT
cat > "$override" <<'HCL'
terraform {
  backend "local" {}
}
HCL

"$tf" bootstrap init -input=false -reconfigure
"$tf" bootstrap apply

rm -f "$override"
# The state moves from terraform.tfstate into the bucket.
"$tf" bootstrap init -input=false -migrate-state -force-copy
rm -f "$root/terraform.tfstate" "$root/terraform.tfstate.backup"
echo "State bucket created; bootstrap/ state is now in s3://mairie360-tfstate/bootstrap.tfstate."
