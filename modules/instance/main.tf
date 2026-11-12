# Resources of one instance (one machine running the platform for one town
# hall environment).
#
# Vault (MAIR-617): the secrets that exist nowhere but on the instance, plus
# the external values the CI reads (MAIR-803). Only
# the secrets are created here, never a value: role k8s_instance_secrets of
# mairie360/ansible adds the versions, finds the secrets by path and name, and
# stops when one is missing. Keep the names in sync with its vault_entries.

locals {
  vault_path = "/${var.org_id}/${var.env_name}"

  vault_secrets = {
    restic-password = "RESTIC_PASSWORD of the backup bucket. Lost: every backup is unreadable."
    admin-password  = "Plaintext first password of the town hall admin account (the instance only holds its hash)."
    sealing-keys    = "One version per sealed-secrets key of the instance (kubectl apply each to restore). Lost: every committed secrets.yaml is undecryptable after a reinstall."
    # MAIR-803: external values the role used to ask the operator for on every
    # first sealing. Stored once (by the role when passed, or with the scw CLI),
    # then read by the CI runs.
    resend-api-key = "Resend API key of the instance (SMTP_PASSWORD of core-api and Keycloak)."
    cockpit-token  = "Scaleway Cockpit token of the instance (COCKPIT_TOKEN of the OpenTelemetry collector)."
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
