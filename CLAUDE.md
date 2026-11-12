# CLAUDE.md

Terraform for the Scaleway resources of Mairie 360 (`mairie360/Infra`, epic MAIR-613). Read
`README.md` first; the agreed design: machines are **imported** (`import`
blocks, `prevent_destroy`, image changes ignored), never recreated; buckets are
rebuilt from scratch; secrets are created here and filled by `mairie360/ansible`.

- Roots: `bootstrap/` (state bucket) and `iam/` (CI applications), both applied from a
  workstation only; `orgs/<org>/` (one per group), planned on PRs and applied by
  `.github/workflows/apply.yml` after approval (MAIR-803). Modules
  under `modules/`. The provider is pinned in the roots (`versions.tf` +
  committed `.terraform.lock.hcl`, several platforms), not in modules.
- Never run `apply` (local or the Apply workflow) without the user's go-ahead; `plan` is fine.
  Use `scripts/tf.sh <root> <cmd>` (sets the S3 backend credentials).
- CI keys stay least-privilege (`iam/tests/`): no IAM, no `*Delete`, no `*FullAccess`, the plan
  key read-only; a new resource type in `orgs/` may need a new permission set in `iam/`.
- Every resource sets `lifecycle { prevent_destroy = true }`
  (`tests/check_prevent_destroy.py`, no exemption); secrets also set `protected = true`.
- The vault secret names and the `/<org>/<env>` path are a contract with role
  `k8s_instance_secrets` of `ansible` (`vault_entries`, `vault_path`).
- CI: `.github/workflows/cicd.yml` calls `terraform_cicd.yml` of `mairie360/CICD` pinned by
  tag (`cicd_version` = same tag); new roots go in its `roots` input.
- Every change ships a `terraform test` (`<root>/tests/*.tftest.hcl`,
  `mock_provider "scaleway"`).
- Commits: Conventional Commits, English; Jira ↔ GitHub flow of the root
  `CLAUDE.md`.
