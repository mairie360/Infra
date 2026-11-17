# Resources of one instance (one machine running the platform for one town
# hall environment).
#
# Vault (MAIR-617): the secrets that exist nowhere but on the instance, plus
# the external values the CI reads (MAIR-803). Only
# the secrets are created here, never a value: role k8s_instance_secrets of
# mairie360/ansible adds the versions, finds the secrets by path and name, and
# stops when one is missing. Keep the names in sync with its vault_entries.

module "naming" {
  source = "../naming"

  org_id   = var.org_id
  env_name = var.env_name
}

locals {
  vault_path = module.naming.vault_path

  vault_secrets = {
    restic-password = "RESTIC_PASSWORD of the backup bucket. Lost: every backup is unreadable."
    admin-password  = "Plaintext first password of the town hall admin account (the instance only holds its hash)."
    sealing-keys    = "One version per sealed-secrets key of the instance (kubectl apply each to restore). Lost: every committed secrets.yaml is undecryptable after a reinstall."
    # MAIR-803: external values the role used to ask the operator for on every
    # first sealing. Stored once (by the role when passed, or with the scw CLI),
    # then read by the CI runs.
    resend-api-key = "Resend API key of the instance (SMTP_PASSWORD of core-api and Keycloak)."
    cockpit-token  = "Scaleway Cockpit token of the instance (COCKPIT_TOKEN of the OpenTelemetry collector)."
    # MAIR-619: the key of each bucket, limited to it (iam/ application and
    # bucket policy). JSON {"access_key", "secret_key"}, written by
    # scripts/issue-bucket-keys.sh, never typed.
    backup-s3-key    = "S3 key of the backup bucket only (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY of the backup CronJob), JSON access_key + secret_key."
    elearning-s3-key = "S3 key of the e-learning bucket only (S3_ACCESS_KEY / S3_SECRET_KEY of elearning-api), JSON access_key + secret_key."
  }
}

resource "scaleway_secret" "vault" {
  for_each = local.vault_secrets

  name        = each.key
  path        = local.vault_path
  description = each.value
  type        = "opaque"
  # Neither the API nor Terraform deletes a protected secret: losing one of
  # these values is not recoverable.
  protected  = true
  project_id = var.project_id
  region     = var.region
  tags       = ["mairie360", "org:${var.org_id}", "env:${var.env_name}", "managed-by:terraform"]

  lifecycle {
    prevent_destroy = true
  }
}

# The machine of the instance (MAIR-637): imported when it already exists
# (orgs/<org>/imports.tf), created otherwise.
module "machine" {
  source = "../machine"

  name                = coalesce(var.machine.name, "${var.org_id}-${var.env_name}")
  type                = var.machine.type
  root_volume_size_gb = var.machine.root_volume_size_gb
  project_id          = var.project_id
  tags                = [var.org_id, var.env_name]
}
