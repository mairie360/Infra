# MAIR-618: the backup bucket of an instance is versioned and locked in
# COMPLIANCE mode. Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  org_id     = "mairie360"
  env_name   = "prod"
  project_id = "00000000-0000-0000-0000-000000000000"
  machine    = { type = "POP2-2C-8G", root_volume_size_gb = 30 }
}

run "backup_bucket_is_versioned_and_locked_30_days" {
  command = apply

  assert {
    condition     = scaleway_object_bucket.backup.name == "mairie360-backups-prod" && output.backup_bucket == "mairie360-backups-prod"
    error_message = "One backup bucket per instance: <org>-backups-<env>."
  }

  assert {
    condition     = scaleway_object_bucket.backup.object_lock_enabled && scaleway_object_bucket.backup.versioning[0].enabled
    error_message = "Object lock (set at creation only) and versioning are on."
  }

  assert {
    condition = (
      scaleway_object_bucket_lock_configuration.backup.rule[0].default_retention[0].mode == "COMPLIANCE"
      && scaleway_object_bucket_lock_configuration.backup.rule[0].default_retention[0].days == 30
    )
    error_message = "Every version is locked 30 days in COMPLIANCE mode (nobody can delete it)."
  }

  assert {
    condition     = scaleway_object_bucket_acl.backup.acl == "private"
    error_message = "The backup bucket is private."
  }
}

run "noncurrent_versions_purged_only_after_their_lock" {
  command = apply

  assert {
    condition     = one(one(scaleway_object_bucket.backup.lifecycle_rule).noncurrent_version_expiration).noncurrent_days > scaleway_object_bucket_lock_configuration.backup.rule[0].default_retention[0].days
    error_message = "A non-current version expires after its lock, never before."
  }
}

run "refuses_a_shorter_lock" {
  command = plan

  variables {
    backup_lock_days = 7
  }

  expect_failures = [var.backup_lock_days]
}
