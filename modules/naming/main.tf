# Names shared by the roots (MAIR-619): orgs/<org>/ creates the buckets,
# iam/ gives each one its own key and bucket policy. Both read the names here
# so they cannot drift. No resource.

terraform {
  required_version = ">= 1.10"
}

variable "org_id" {
  description = "Group id, e.g. mairie360."
  type        = string
}

variable "env_name" {
  description = "Environment of the instance, e.g. dev."
  type        = string
}

output "buckets" {
  description = "Bucket name of each purpose of the instance."
  value = {
    # restic repository of the backup CronJob (MAIR-618), locked.
    backup = "${var.org_id}-backups-${var.env_name}"
    # course attachments of elearning-api (S3_BUCKET).
    elearning = "${var.org_id}-elearning-${var.env_name}"
  }
}

output "vault_path" {
  description = "Secret Manager path of the instance (vault_path of role k8s_instance_secrets)."
  value       = "/${var.org_id}/${var.env_name}"
}

output "bucket_key_secrets" {
  description = "Vault secret holding the S3 key of each bucket purpose (JSON access_key / secret_key)."
  value = {
    backup    = "backup-s3-key"
    elearning = "elearning-s3-key"
  }
}
