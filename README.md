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
iam/                  IAM applications of the CI (MAIR-803), applied from a workstation only
modules/instance/     resources of one instance: its vault secrets
orgs/mairie360/       group mairie360: instances dev, staging, prod
scripts/tf.sh         terraform in one root, S3 backend credentials from the scw profile
scripts/bootstrap.sh  first creation of the state bucket
scripts/plan-comment.sh  plan output as markdown (PR comment, job summary)
tests/                repository checks run by CI
```

A client group is a copy of `orgs/mairie360/` as `orgs/<org>/` (own Scaleway
project in `terraform.tfvars`, own state key in `backend.tf`, its `envs`).

## Vault of the instance secrets (MAIR-617)

`modules/instance` creates five **protected** Secret Manager secrets per
instance under `/<org>/<env>`: `restic-password`, `admin-password`,
`sealing-keys`, and the external values the CI reads (MAIR-803):
`resend-api-key`, `cockpit-token`. Terraform creates the secrets only, never a value: role
`k8s_instance_secrets` of `ansible` finds them by path and name, adds the
versions and reads them back, and stops when one is missing. Rename nothing
here without changing its `vault_entries`.

A protected secret cannot be deleted, by the API or by Terraform, and every
resource carries `prevent_destroy` (checked in CI by
`tests/check_prevent_destroy.py`).

## Usage

Requirements (workstation): Terraform 1.17, the scw CLI configured (`scw init`) with an API
key of the `mairie360` project (`ObjectStorageFullAccess`,
`SecretManagerFullAccess`; `IAMManager` on the organization for `iam/`).

```bash
# Once, ever: create the state bucket (local state first, then moved into it).
# Safe to re-run: while a local state is left, the run applies against it (what
# a stopped run did not create yet, e.g. the bucket ACL), then migrates; the
# local state is only deleted once the bucket holds it.
scripts/bootstrap.sh

# Once, then on any change of iam/: the CI applications (see "CI credentials")
scripts/tf.sh iam apply

# Every change of orgs/: through the CI (below); by hand only as a fallback
scripts/tf.sh orgs/mairie360 plan
scripts/tf.sh orgs/mairie360 apply
```

## Running from the CI (MAIR-803)

The day-to-day path does not need a workstation:

- every pull request gets a `terraform plan` of each `orgs/*` root as a comment
  (`.github/workflows/plan.yml`, read-only key);
- `Actions > Apply > Run workflow` on `main` plans, shows the plan in the job
  summary, then waits for a reviewer of the `infra-apply` environment and
  applies exactly that plan (`.github/workflows/apply.yml`). One apply at a time.

`bootstrap/` and `iam/` stay workstation-only (`scripts/tf.sh <root> apply`): the
CI keys cannot manage IAM or create buckets, so a workflow can never widen its
own rights. The workstation is also the fallback when GitHub is unavailable.

### CI credentials

`iam/` creates one IAM application per workflow, limited to the group's
project: `mairie360-ci-terraform-plan` (read-only), `mairie360-ci-terraform-apply`
(state, create/update secrets; no delete, no IAM), `mairie360-ci-ansible`
(read and add secret versions, for `mairie360/ansible`). No API key is created by
Terraform: it would sit in the state. Once, after `scripts/tf.sh iam apply`:

```bash
scripts/tf.sh iam output -json ci_application_ids
scw iam api-key create application-id=<id> description="mairie360/Infra infra-plan" -o json
```

then store `access_key` / `secret_key` as the secrets `SCW_ACCESS_KEY` /
`SCW_SECRET_KEY` of the GitHub environment (`infra-plan`, `infra-apply` here;
`ops-*` in `mairie360/ansible`), and set the variables `SCW_DEFAULT_PROJECT_ID`
and `SCW_DEFAULT_ORGANIZATION_ID`. `infra-apply` requires a reviewer and only
deploys from `main`. To rotate a key: create the new one, update the secret,
delete the old one (`scw iam api-key delete`).

Any branch of this repository can run the plan workflow with the read-only key:
it reads the state and the secrets' metadata, never a secret value.

## State

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
the `prevent_destroy` check and `tests/test_workflows.py` (who may hold the apply key). `gdpr-pr.yml` checks the GDPR question of the PR description.
