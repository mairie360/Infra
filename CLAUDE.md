# CLAUDE.md

Terraform for the Scaleway resources of Mairie 360 (`mairie360/Infra`, epic MAIR-613). Read
`README.md` first; the agreed design: machines are **imported** (`import`
blocks, `prevent_destroy`, image changes ignored), never recreated; buckets are
rebuilt from scratch; secrets are created here and filled by `mairie360/ansible`.

- Roots: `bootstrap/` (state bucket), `orgs/<org>/` (one per group). Modules
  under `modules/`. The provider is pinned in the roots (`versions.tf` +
  committed `.terraform.lock.hcl`, several platforms), not in modules.
- Never run `apply` without the user's go-ahead; `plan` is fine. Use
  `scripts/tf.sh <root> <cmd>` (sets the S3 backend credentials).
- Every resource sets `lifecycle { prevent_destroy = true }`
  (`tests/check_prevent_destroy.sh`); secrets also set `protected = true`.
- The vault secret names and the `/<org>/<env>` path are a contract with role
  `k8s_instance_secrets` of `ansible` (`vault_entries`, `vault_path`).
- Every change ships a `terraform test` (`<root>/tests/*.tftest.hcl`,
  `mock_provider "scaleway"`).
- Commits: Conventional Commits, English; Jira ↔ GitHub flow of the root
  `CLAUDE.md`.
