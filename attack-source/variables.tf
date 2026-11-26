variable "project_id" {
  description = "Scaleway project of the attack source: mairie360-attack (output attack_project_id of iam/), never the platform's project, so the key that creates and destroys the source cannot reach a machine of the platform."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.project_id)) && var.project_id != "716a44bd-7d6f-4940-87ca-711e62799cd0"
    error_message = "project_id is the UUID of the mairie360-attack project (iam/ output attack_project_id), not the platform's project."
  }
}

variable "enabled" {
  description = "Whether the attack source server exists: true for a campaign window, false (destroyed) otherwise."
  type        = bool
  default     = false
}

variable "zone" {
  description = "Zone of the attack source: another zone than the instances (fr-par-1), so its traffic crosses the Internet like an attacker's."
  type        = string
  default     = "fr-par-2"

  validation {
    condition     = var.zone != "fr-par-1"
    error_message = "The attack source runs outside the zone of the instances (fr-par-1)."
  }
}

variable "type" {
  description = "Commercial type of the server."
  type        = string
  default     = "DEV1-M"
}

variable "image" {
  description = "Image of the server, installed fresh for each campaign."
  type        = string
  default     = "ubuntu_noble"
}

variable "ssh_ranges" {
  description = "Ranges allowed to reach SSH (22) on the source; everything else inbound is dropped."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "spoof_test" {
  description = <<-EOT
    Monthly spoofed e-mail test (.github/workflows/spoof-test.yml): with enabled, the server
    opens SMTP egress (Scaleway's default security off, verified account) and, at boot, sends
    one e-mail with a forged From: in a protected domain to the Resend receiving inbox; the
    workflow then checks the DMARC verdict and destroys the server. null outside the test.
  EOT
  type = object({
    to    = string
    from  = string
    token = string
  })
  default = null

  validation {
    condition = var.spoof_test == null ? true : (
      can(regex("^[^@\\s]+@mairie360\\.fr$", var.spoof_test.to))
      && can(regex("^[^@\\s]+@(mairie360-eip\\.fr|mairie360\\.fr)$", var.spoof_test.from))
      && can(regex("^[a-z0-9]{16,64}$", var.spoof_test.token))
    )
    error_message = "spoof_test sends to the Resend inbox (@mairie360.fr) only, as an address of a mairie360 domain, with a 16-64 character [a-z0-9] token."
  }

  validation {
    condition     = var.spoof_test == null || var.enabled
    error_message = "spoof_test needs enabled = true: the e-mail is sent by the server."
  }
}
