# Infra

Scaleway resources of the Mairie 360 platform, as code. One of the three
infrastructure repositories:

| Repository | Owns |
| --- | --- |
| `Infra` (this one) | Scaleway resources: Secret Manager vault, state bucket, then machines, buckets, keys (epic MAIR-613) |
| [`ansible`](https://github.com/mairie360/ansible) | what runs on the machines (k3s, WireGuard, Argo CD), and the values written into the vault |
| [`Deploiment`](https://github.com/mairie360/Deploiment) | what runs in Kubernetes (Argo CD + Helm chart) |

Nothing is created by hand in the Scaleway console: a missing resource is added
here and applied.

## Layout

```
bootstrap/            state bucket mairie360-tfstate (versioned, private)
modules/instance/     resources of one instance: its vault secrets
orgs/mairie360/       group mairie360: instances dev, staging, prod
scripts/tf.sh         terraform in one root, S3 backend credentials from the scw profile
scripts/bootstrap.sh  first creation of the state bucket
tests/                repository checks run by CI
```

A client group is a copy of `orgs/mairie360/` as `orgs/<org>/` (own Scaleway
project in `terraform.tfvars`, own state key in `backend.tf`, its `envs`).

## Vault of the instance secrets (MAIR-617)

`modules/instance` creates three **protected** Secret Manager secrets per
instance under `/<org>/<env>`: `restic-password`, `admin-password`,
`sealing-keys`. Terraform creates the secrets only, never a value: role
`k8s_instance_secrets` of `ansible` finds them by path and name, adds the
versions and reads them back, and stops when one is missing. Rename nothing
here without changing its `vault_entries`.

A protected secret cannot be deleted, by the API or by Terraform, and every
resource carries `prevent_destroy` (checked in CI by
`tests/check_prevent_destroy.py`).

## Usage

Requirements: Terraform 1.17, the scw CLI configured (`scw init`) with an API
key of the `mairie360` project (`ObjectStorageFullAccess`,
`SecretManagerFullAccess`).

```bash
# Once, ever: create the state bucket (local state first, then moved into it).
# Safe to re-run: while a local state is left, the run applies against it (what
# a stopped run did not create yet, e.g. the bucket ACL), then migrates; the
# local state is only deleted once the bucket holds it.
scripts/bootstrap.sh

# Every change
scripts/tf.sh orgs/mairie360 plan
scripts/tf.sh orgs/mairie360 apply
```

The state is in `s3://mairie360-tfstate/<root>.tfstate`, versioned: restore
the previous version of the object to roll a broken state back. There is no
state lock: one apply at a time.

## Checks

```bash
terraform fmt -recursive -check
for r in bootstrap modules/instance orgs/mairie360; do
  terraform -chdir=$r init -backend=false && terraform -chdir=$r validate && terraform -chdir=$r test
done
python3 tests/check_prevent_destroy.py
python3 -m unittest discover -s tests   # the check and scripts/*.sh, terraform and scw stubbed
```

The tests mock the Scaleway provider: they need no account and touch nothing.
CI (`.github/workflows/cicd.yml`) calls `terraform_cicd.yml` of `mairie360/CICD`: the same
checks per root, plus Semgrep, Gitleaks and a Trivy IaC scan (accepted risks in `.trivyignore`),
and the `prevent_destroy` check. `gdpr-pr.yml` checks the GDPR question of the PR description.
