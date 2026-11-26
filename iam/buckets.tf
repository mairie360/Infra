# One key per bucket (MAIR-619).
#
# Scaleway grants Object Storage access when BOTH the IAM policy of the
# principal AND, if the bucket has one, the bucket policy allow it; a bucket
# with a policy refuses every principal it does not list (the organization
# owner can always edit the policy). So:
#   - each instance bucket gets its own IAM application, with object rights on
#     the project (IAM cannot name a bucket), and
#   - EVERY bucket of the project gets a bucket policy that lists who may use
#     it: its own application for objects, the CI applications for the bucket
#     configuration only, the operators for everything.
# A bucket application thus reaches its own bucket and nothing else, the
# Terraform state included. A new bucket in the project must get a policy here
# too, or every bucket application can read it.
#
# Order: orgs/<org> creates the buckets (CI apply), then this root (workstation)
# sets their policies, then scripts/issue-bucket-keys.sh puts one key per
# application into the vault (README, "Bucket keys").

module "naming" {
  source   = "../modules/naming"
  for_each = toset(var.envs)

  org_id   = var.org_id
  env_name = each.key
}

locals {
  # "<env>/<purpose>" => env, purpose, bucket name and vault secret,
  # e.g. "prod/backup" => mairie360-backups-prod, /mairie360/prod/backup-s3-key.
  instance_buckets = merge([
    for env, n in module.naming : {
      for purpose, bucket in n.buckets : "${env}/${purpose}" => {
        env     = env
        purpose = purpose
        name    = bucket
        secret  = "${n.vault_path}/${n.bucket_key_secrets[purpose]}"
      }
    }
  ]...)

  # What each bucket application does with the objects of its bucket. No
  # s3:DeleteObjectVersion: a delete only adds a marker (versioned buckets).
  object_actions = {
    # restic: init, backup, forget --prune, check.
    backup = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    # elearning-api: presigned GET today, uploads and deletes next.
    elearning = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
  }

  # Bucket configuration Terraform reads (plan) and writes (apply). No object
  # action: the CI never reads a backup or an attachment.
  config_read = [
    "s3:ListBucket",
    "s3:GetBucketAcl",
    "s3:GetBucketCORS",
    "s3:GetBucketLocation",
    "s3:GetBucketTagging",
    "s3:GetBucketVersioning",
    "s3:GetBucketWebsite",
    "s3:GetLifecycleConfiguration",
    "s3:GetBucketObjectLockConfiguration",
  ]
  config_write = [
    "s3:PutBucketAcl",
    "s3:PutBucketCORS",
    "s3:PutBucketTagging",
    "s3:PutBucketVersioning",
    "s3:PutLifecycleConfiguration",
    "s3:PutBucketObjectLockConfiguration",
  ]

  operators = [for id in var.operator_user_ids : "user_id:${id}"]

  ci_plan  = "application_id:${scaleway_iam_application.ci["ci-terraform-plan"].id}"
  ci_apply = "application_id:${scaleway_iam_application.ci["ci-terraform-apply"].id}"
}

resource "scaleway_iam_application" "bucket" {
  for_each = local.instance_buckets

  name        = "${each.value.name}-s3"
  description = "S3 key of ${each.value.name} only (bucket policy). Key in the vault: ${each.value.secret}."
  tags        = [var.org_id, "bucket-key", "managed-by=terraform"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "bucket" {
  for_each = local.instance_buckets

  name           = "${each.value.name}-s3"
  description    = "Object rights of ${each.value.name}-s3; the bucket policies limit them to ${each.value.name}."
  application_id = scaleway_iam_application.bucket[each.key].id
  tags           = [var.org_id, "bucket-key", "managed-by=terraform"]

  rule {
    project_ids = [var.project_id]
    permission_set_names = [
      "ObjectStorageBucketsRead",
      "ObjectStorageObjectsRead",
      "ObjectStorageObjectsWrite",
      "ObjectStorageObjectsDelete",
    ]
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_policy" "instance" {
  for_each = local.instance_buckets

  bucket     = each.value.name
  project_id = var.project_id
  region     = "fr-par"
  policy = jsonencode({
    Version = "2023-04-17"
    Id      = "${each.value.name}-access"
    Statement = concat(
      [
        {
          Sid       = "own-key-objects"
          Effect    = "Allow"
          Principal = { SCW = "application_id:${scaleway_iam_application.bucket[each.key].id}" }
          Action    = local.object_actions[each.value.purpose]
          Resource  = [each.value.name, "${each.value.name}/*"]
        },
        {
          Sid       = "ci-plan-configuration"
          Effect    = "Allow"
          Principal = { SCW = local.ci_plan }
          Action    = local.config_read
          Resource  = [each.value.name]
        },
        {
          Sid       = "ci-apply-configuration"
          Effect    = "Allow"
          Principal = { SCW = local.ci_apply }
          Action    = concat(local.config_read, local.config_write)
          Resource  = [each.value.name]
        },
      ],
      length(local.operators) == 0 ? [] : [{
        Sid       = "operators"
        Effect    = "Allow"
        Principal = { SCW = local.operators }
        Action    = ["s3:*"]
        Resource  = [each.value.name, "${each.value.name}/*"]
      }],
    )
  })

  lifecycle {
    prevent_destroy = true
  }
}

# The Terraform state bucket (bootstrap/): the CI reads (plan) and writes
# (apply) the state objects; no bucket application can.
resource "scaleway_object_bucket_policy" "state" {
  bucket     = var.state_bucket
  project_id = var.project_id
  region     = "fr-par"
  policy = jsonencode({
    Version = "2023-04-17"
    Id      = "${var.state_bucket}-access"
    Statement = concat(
      [
        {
          Sid       = "ci-plan-state"
          Effect    = "Allow"
          Principal = { SCW = local.ci_plan }
          Action    = concat(local.config_read, ["s3:GetObject"])
          Resource  = [var.state_bucket, "${var.state_bucket}/*"]
        },
        {
          Sid       = "ci-apply-state"
          Effect    = "Allow"
          Principal = { SCW = local.ci_apply }
          Action    = concat(local.config_read, ["s3:GetObject", "s3:PutObject"])
          Resource  = [var.state_bucket, "${var.state_bucket}/*"]
        },
        {
          # Releasing the state lock deletes <key>.tflock; nothing else.
          Sid       = "ci-apply-state-lock"
          Effect    = "Allow"
          Principal = { SCW = local.ci_apply }
          Action    = ["s3:DeleteObject"]
          Resource  = ["${var.state_bucket}/*.tflock"]
        },
        {
          # The spoofed e-mail test (campaigns.tf) applies attack-source/ only:
          # its state and lock, nothing else of the bucket.
          Sid       = "ci-spoof-test-state"
          Effect    = "Allow"
          Principal = { SCW = local.ci_spoof }
          Action    = ["s3:GetObject", "s3:PutObject"]
          Resource  = ["${var.state_bucket}/attack-source.tfstate", "${var.state_bucket}/attack-source.tfstate.tflock"]
        },
        {
          Sid       = "ci-spoof-test-state-lock"
          Effect    = "Allow"
          Principal = { SCW = local.ci_spoof }
          Action    = ["s3:DeleteObject"]
          Resource  = ["${var.state_bucket}/attack-source.tfstate.tflock"]
        },
        {
          Sid       = "ci-spoof-test-list"
          Effect    = "Allow"
          Principal = { SCW = local.ci_spoof }
          Action    = ["s3:ListBucket"]
          Resource  = [var.state_bucket]
        },
      ],
      length(local.operators) == 0 ? [] : [{
        Sid       = "operators"
        Effect    = "Allow"
        Principal = { SCW = local.operators }
        Action    = ["s3:*"]
        Resource  = [var.state_bucket, "${var.state_bucket}/*"]
      }],
    )
  })

  lifecycle {
    prevent_destroy = true
  }
}
