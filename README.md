# Infra

Scaleway resources of the Mairie 360 platform, as code. One of the three
infrastructure repositories:

| Repository | Owns |
| --- | --- |
| `Infra` (this one) | Scaleway resources: Secret Manager vault, state bucket, machines, then buckets, keys (epic MAIR-613) |
| [`ansible`](https://github.com/mairie360/ansible) | what runs on the machines (k3s, WireGuard, Argo CD), and the values written into the vault |
| [`Deploiment`](https://github.com/mairie360/Deploiment) | what runs in Kubernetes (Argo CD + Helm chart) |

Nothing is created by hand in the Scaleway console: a missing resource is added
here and applied.

## Layout

```
bootstrap/            state bucket mairie360-tfstate (versioned, private)
iam/                  IAM applications of the CI (MAIR-803) and of each bucket, bucket policies (MAIR-619), applied from a workstation only
modules/instance/     resources of one instance: vault secrets, machine, buckets, Cockpit data sources
modules/machine/      one machine: server + routed IPv4 + routed IPv6 + security group (public ports)
modules/dns/          public names of one instance: <host>.<env>.<zone> -> its machine
modules/naming/       bucket and vault names shared by orgs/ and iam/
orgs/mairie360/       group mairie360: instances dev, staging, prod, Argo CD machine
scripts/tf.sh         terraform in one root, S3 backend credentials from the scw profile
scripts/bootstrap.sh  first creation of the state bucket
scripts/plan-comment.sh  plan output as markdown (PR comment, job summary)
scripts/issue-bucket-keys.sh  one S3 key per bucket, straight into the vault
scripts/issue-cockpit-tokens.sh  one push-only Cockpit token per instance (and the hub probe), straight into the vault
scripts/push-alert-rules.sh   alert rules of alerts/ to the Cockpit rulers (Apply workflow)
alerts/               alert rules, one rule group per file
tests/                repository checks run by CI
```

A client group is a copy of `orgs/mairie360/` as `orgs/<org>/` (own Scaleway
project in `terraform.tfvars`, own state key in `backend.tf`, its `envs`).

## Machines (MAIR-637)

`modules/machine` holds one Scaleway Instance with its routed IPv4 and IPv6. The
machines made in the console before this repository (`argocd hub`,
`mairie360-{dev,staging,prod}`) are **imported, never recreated**: their ids are
in `imported_machines` of `orgs/mairie360/terraform.tfvars`, read by the import
blocks of `orgs/mairie360/imports.tf` (a no-op once they are in the state, so
they stay). `prevent_destroy` on every resource, the image is ignored after
creation (the OS is upgraded in place by `mairie360/ansible`), a type change
resizes in place, and the CI refuses a plan that destroys anything. A client
group without `imported_machines` gets new machines (Ubuntu 26.04).

The first apply adopts the four machines and only adds the missing `org`/`env`
tags of dev and prod; check that its plan shows `0 to destroy` and no server
replacement.

The output `ansible_hosts` (`<org>-argocd`, `<org>-<env>` => Ansible group,
`env_name`, public IPv4) is what `mairie360/ansible` builds its gitignored
`inventory/hosts.yml` from (`scripts/inventory-from-terraform.py`), so public
addresses are never typed nor committed:

```bash
scripts/tf.sh orgs/mairie360 output -json ansible_hosts > /tmp/hosts.json
# in mairie360/ansible:
scripts/inventory-from-terraform.py --org mairie360 /tmp/hosts.json
```

### Tiers

An instance machine is sized by its **tier** (`instances.<env>.machine.tier` of
`terraform.tfvars`, table `local.tiers` of `modules/instance/main.tf`):

| Tier | Type | Root volume |
| --- | --- | --- |
| `small` | `POP2-2C-8G` | 30 GB (dev, staging, prod today) |
| `medium` | `POP2-4C-16G` | 60 GB |
| `large` | `POP2-8C-32G` | 120 GB |

`type` and `root_volume_size_gb` override the tier. Moving up a tier resizes the
machine in place (stop, change, start: plan it in a maintenance window). The
volume can only grow: moving down would ask for the smaller tier's size and
fail, so keep the current size explicitly first (for example `tier = "small"`
with `root_volume_size_gb = 120`).

### Security groups

Each machine gets its own security group (`public_ports` of `modules/machine`):
inbound dropped by default, stateful, outbound open (SMTP blocked by Scaleway's
default security, e-mail goes through the Resend API). The ports are the ones
`mairie360/ansible` opens in ufw, the group is a second layer in front of it:

| Machine | Open |
| --- | --- |
| instance | TCP 22, 80, 443 |
| Argo CD (WireGuard hub) | TCP 22, UDP 51820 |
| n8n | TCP 22, 80, 443 |

k3s (6443) is never public: the module refuses it, Argo CD reaches it through
the tunnel. When ansible closes public SSH (`wireguard_close_public_ssh`), drop
22 from the instances here too. Attaching a group is done in place, without a
restart; apply it on dev first and check SSH, the sites and the tunnel.

### DNS

`modules/dns` names every Ingress host of an instance (`login`, `project`,
`calendar`, `message`, `dashboard`, `settings`, `elearning`, `admin`, `auth`)
`<host>.<env>.<dns_zone>`, pointing to the IPv4 of the instance's own machine;
`n8n.<dns_zone>` follows the n8n machine, `extra_records` holds the rest (mail,
verifications). Everything is off while `dns_zone` is null: `mairie360-eip.fr`
is still served by o2switch. To switch: create the zone in Scaleway Domains,
copy the records Terraform does not manage into `extra_records` (Resend
DKIM/SPF/MX first, with `priority` on the MX records), apply, then move the name servers at the registrar.

## Backup buckets (MAIR-618)

Each instance gets `<org>-backups-<env>`, the restic repository of the backup
CronJob (`backup.s3.bucket` in Deploiment). Versioned, private, and **locked in
COMPLIANCE mode for 30 days** (`backup_lock_days`): no version written in the
last 30 days can be deleted or overwritten, by the instance key, a CI key or the
organization owner. `restic forget --prune` still works: on a versioned bucket a
delete only adds a delete marker (restic >= 0.13 sends the Content-MD5 that
object lock requires). A lifecycle rule purges non-current versions after 31
days, once their lock is over. Object lock can only be set when a bucket is
created: the hand-made `mairie360-backup-<env>` buckets are not converted.

Rollout, per env (dev first):

1. Apply: the bucket is created empty.
2. Deploiment points `backup.s3.bucket` at it; the next CronJob run (or
   `kubectl create job --from=cronjob/<release>-backup`) runs `restic init`
   there with the same `RESTIC_PASSWORD` and takes a first snapshot.
3. After 30 days of backups in the new bucket, empty and delete the old
   `mairie360-backup-<env>` bucket (not managed here, it holds no locked data).

The COMPLIANCE lock cannot be shortened nor removed, even by Scaleway support:
a wrong `backup_lock_days` costs storage for that many days.

## Bucket keys (MAIR-619)

Each instance bucket (`<org>-backups-<env>`, `<org>-elearning-<env>`, the
latter rebuilt from scratch: the shared hand-made `mairie360-eleartning-storage`
is dropped) has **its own IAM application and key**, and only reaches that
bucket. Scaleway lets a request through when the principal's IAM policy AND,
if there is one, the bucket policy allow it, and a bucket with a policy refuses
every principal it does not list. So `iam/buckets.tf` gives:

- each bucket application object rights on the project (IAM cannot name a
  bucket: `ObjectStorageObjects{Read,Write,Delete}`, `ObjectStorageBucketsRead`);
- **every bucket of the project a bucket policy**: its own application for its
  objects (`ListBucket`, `Get/Put/DeleteObject`, never `DeleteObjectVersion`),
  the CI plan / apply applications for the bucket configuration only (no
  object), the `operator_user_ids` for everything. The state bucket gets one
  too (CI applications only), or every bucket key could read the state. A new
  bucket in the project needs its policy there.

A bucket policy applies to everyone it does not list, **the organization owner
included** (the first `iam apply` locked its own state bucket). Anyone who runs
Terraform with a personal key must be in `operator_user_ids`
(`scw iam user list`, `iam/terraform.tfvars`) before `iam/` is applied. The
owner can still read and edit a bucket's policy with their key, which is the
way back from a lockout: add an `operators` statement, then `terraform state
push errored.tfstate` if an apply could not save its state.

Keys are never typed, printed nor stored in the state: once per bucket,

```bash
scripts/tf.sh orgs/mairie360 apply   # or the Apply workflow: buckets + vault secrets
scripts/tf.sh iam apply              # applications + bucket policies
scripts/issue-bucket-keys.sh         # one key per application -> /<org>/<env>/<purpose>-s3-key
```

then the ansible role `k8s_instance_secrets` reads `backup-s3-key` and
`elearning-s3-key` from the vault and seals them (playbooks/secrets.yml). Once
every instance runs on its new keys, delete the old hand-made keys with
project-wide rights (`scw iam api-key list`). Rotation:
`scripts/issue-bucket-keys.sh --rotate <env>/<purpose>`, reseal, then delete the
previous key it prints.

## Observability (MAIR-620)

Each instance gets two Cockpit data sources, `<org>-<env>-metrics` (31 days)
and `<org>-<env>-traces` (7 days), for its OpenTelemetry Collector
(Deploiment `charts/observability`). The token the collector pushes with is a
Cockpit token limited to `write_only_metrics` + `write_only_traces`, issued
once per instance straight into `/<org>/<env>/cockpit-token` (never in the
state); ansible seals it as `COCKPIT_TOKEN`:

```bash
scripts/tf.sh orgs/mairie360 apply                  # or the Apply workflow
scripts/issue-cockpit-tokens.sh mairie360           # envs without a token yet
scripts/tf.sh orgs/mairie360 output -json instances | jq '.[].cockpit_endpoints'
```

The endpoints go into `observability.cockpit` of each instance's Deploiment
values, with `global.observability.enabled: true`.

The apply key holds `ObservabilityFullAccess`: Cockpit has no permission set
between read-only and full access. The plan key stays `ObservabilityReadOnly`.

## Alert channel (MAIR-623)

Every alert of a group is **e-mailed** through the Cockpit alert manager of its
project (`orgs/<org>/alerting.tf`), to `alert_emails` (a team mailbox, never a
person's). Cockpit only sends e-mail; managed (preconfigured) alerts stay off,
the group's rules are its own (`alerts/`, MAIR-621 / MAIR-622). mairie360's alert
manager was enabled in the console before this repository and is adopted
(`import_alert_manager = true`); a new client project leaves it false.

## External probe (MAIR-621)

The platform is watched **from outside the instances**: an OpenTelemetry
Collector on the group's Argo CD machine (role `hub_probe` of
`mairie360/ansible`) checks every instance's public URLs each minute and pushes
the results to the group's Cockpit source `<org>-probes` (`orgs/<org>/probes.tf`).
Its push-only token lives in `/<org>/hub/cockpit-token`
(`scripts/issue-cockpit-tokens.sh <org> hub`).

The rules (`alerts/group/probes.yml`): `SiteDown` (no 2xx for 5 min),
`SiteUnreachable` (DNS/TLS/TCP error for 5 min), `ProbeSilent` (no result for
15 min: the machine or the probe is down). They are pushed to the Cockpit ruler
by `scripts/push-alert-rules.sh <org>`, run by the Apply workflow after the
apply (input `alert_rules`, default on, also without Terraform change), and
e-mailed by the alert manager (MAIR-623). See `alerts/README.md`.

## Backup alert (MAIR-622)

After every successful run, the backup CronJob of an instance (Deploiment
`charts/backup`) pushes `mairie360_backup_last_success_timestamp_seconds` to
the instance's collector, hence to `<org>-<env>-metrics`.
`alerts/instance/backups.yml` (pushed to every instance by
`scripts/push-alert-rules.sh`) raises `BackupMissed` when the last success is
older than 7 h (the CronJob runs every 6 h), or when nothing was reported for
8 h (a CronJob that never runs or cannot reach the collector). The same file
alerts on the weekly restore test of the instance (`charts/backup`
`restoreTest`): `RestoreTestMissed` after 8 days without a success, and
`RestoreTooSlow` when restoring the database took more than 1 h (half of the
2 h RTO, the rest is the machine rebuild). It needs `global.observability.enabled`
on the instance (MAIR-620).

## Vault of the instance secrets (MAIR-617)

`modules/instance` creates seven **protected** Secret Manager secrets per
instance under `/<org>/<env>`: `restic-password`, `admin-password`,
`sealing-keys`, the external values the CI reads (MAIR-803):
`resend-api-key`, `cockpit-token`, and the bucket keys (MAIR-619):
`backup-s3-key`, `elearning-s3-key`. Terraform creates the secrets only, never a value: role
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
the previous version of the object to roll a broken state back. Every apply
(local or CI) takes a lock, `<root>.tfstate.tflock` written with a conditional
write (`use_lockfile`, Terraform >= 1.11, `If-None-Match` supported by Scaleway
Object Storage): a second apply fails with "Error acquiring the state lock"
instead of overwriting the state. The CI plans run with `-lock=false` (read-only
key). A lock left by a killed run: check nobody applies, then
`scripts/tf.sh <root> force-unlock <lock id>`.

## Checks

```bash
terraform fmt -recursive -check
for r in bootstrap modules/instance orgs/mairie360; do
  terraform -chdir=$r init -backend=false && terraform -chdir=$r validate && terraform -chdir=$r test
done
python3 -m pip install --user pyyaml==6.0.3   # for tests/test_workflows.py, the version CI installs
python3 tests/check_prevent_destroy.py
python3 -m unittest discover -s tests   # the check and scripts/*.sh, terraform and scw stubbed
```

The tests mock the Scaleway provider: they need no account and touch nothing.
CI (`.github/workflows/cicd.yml`) calls `terraform_cicd.yml` of `mairie360/CICD`: the same
checks per root, plus Semgrep, Gitleaks and a Trivy IaC scan (accepted risks in `.trivyignore`),
the `prevent_destroy` check and `tests/test_workflows.py` (who may hold the apply key). `gdpr-pr.yml` checks the GDPR question of the PR description.
