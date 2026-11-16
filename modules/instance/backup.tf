# Backup bucket of the instance (MAIR-618): the restic repository of the
# backup CronJob (Deploiment charts/backup). Built from scratch next to the
# hand-made, unlocked mairie360-backup-<env> buckets, which are dropped once
# the new ones hold 30 days of backups (README, "Backup buckets").
#
# Versioning + object lock in COMPLIANCE mode: for `backup_lock_days` after it
# is written, no object version can be deleted or overwritten by anyone, the
# key of the instance, a CI key or the organization owner included. A restic
# `forget --prune` (or an attacker with the key) only adds delete markers; the
# locked versions stay restorable. Non-current versions are purged by the
# lifecycle rule once their lock has expired.

locals {
  backup_bucket = "${var.org_id}-backups-${var.env_name}"
}

resource "scaleway_object_bucket" "backup" {
  name                = local.backup_bucket
  project_id          = var.project_id
  region              = var.region
  object_lock_enabled = true
  tags = {
    managed-by = "terraform"
    purpose    = "restic-backups"
    org        = var.org_id
    env        = var.env_name
  }

  # Required by object lock.
  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "purge-unlocked-noncurrent-versions"
    enabled = true
    # One day past the lock: a version is only purged once it can be.
    noncurrent_version_expiration {
      noncurrent_days = var.backup_lock_days + 1
    }
    abort_incomplete_multipart_upload_days = 1
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_lock_configuration" "backup" {
  bucket     = scaleway_object_bucket.backup.name
  project_id = var.project_id
  region     = var.region

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.backup_lock_days
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_acl" "backup" {
  bucket     = scaleway_object_bucket.backup.id
  project_id = var.project_id
  acl        = "private"

  lifecycle {
    prevent_destroy = true
  }
}
