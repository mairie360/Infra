#!/usr/bin/env bash
# Run terraform in one root of this repository with the S3 backend credentials
# taken from the scw CLI profile (the backend speaks the AWS S3 API):
#
#   scripts/tf.sh orgs/mairie360 plan
#   scripts/tf.sh orgs/mairie360 apply
#
# SCW_PROFILE selects another profile. AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# already set are kept.
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <root, e.g. orgs/mairie360> <terraform command> [args...]" >&2
  exit 2
fi
root=$1
shift

repo=$(cd "$(dirname "$0")/.." && pwd)
if [ ! -d "$repo/$root" ]; then
  echo "no such root: $root" >&2
  exit 2
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  if ! command -v scw >/dev/null; then
    echo "set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY or install the scw CLI (scw init)" >&2
    exit 1
  fi
  AWS_ACCESS_KEY_ID=$(scw config get access-key)
  AWS_SECRET_ACCESS_KEY=$(scw config get secret-key)
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
fi

if [ ! -d "$repo/$root/.terraform" ] && [ "$1" != init ]; then
  terraform -chdir="$repo/$root" init -input=false
fi
exec terraform -chdir="$repo/$root" "$@"
