variable "org_id" {
  description = "Group the instance belongs to (org_id of the Ansible inventory), e.g. mairie360."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.org_id))
    error_message = "org_id is lowercase letters, digits and dashes, like the Ansible org_id."
  }
}

variable "env_name" {
  description = "Environment of the instance (env_name of the Ansible inventory), e.g. dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.env_name))
    error_message = "env_name is lowercase letters, digits and dashes, like the Ansible env_name."
  }
}

variable "project_id" {
  description = "Scaleway project holding the group's resources."
  type        = string
}

variable "region" {
  description = "Scaleway region of the vault."
  type        = string
  default     = "fr-par"
}

variable "machine" {
  description = "Machine of the instance (MAIR-637). name defaults to <org_id>-<env_name>."
  type = object({
    type                = string
    root_volume_size_gb = number
    name                = optional(string)
  })
}

variable "backup_lock_days" {
  description = "COMPLIANCE object lock of every backup version, in days (MAIR-618). Can be raised, never lowered by anyone before the versions expire."
  type        = number
  default     = 30

  validation {
    condition     = var.backup_lock_days >= 30
    error_message = "Backups stay locked at least 30 days (agreed for MAIR-618)."
  }
}
