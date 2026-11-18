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
  description = <<-EOT
    Machine of the instance. tier picks its size (see local.tiers of main.tf:
    small, medium, large); type and root_volume_size_gb override the tier. name
    defaults to <org_id>-<env_name>.
  EOT
  type = object({
    tier                = optional(string)
    type                = optional(string)
    root_volume_size_gb = optional(number)
    name                = optional(string)
  })

  validation {
    condition     = var.machine.tier == null ? true : contains(["small", "medium", "large"], var.machine.tier)
    error_message = "machine.tier is small, medium or large."
  }

  validation {
    condition     = var.machine.tier != null || (var.machine.type != null && var.machine.root_volume_size_gb != null)
    error_message = "machine needs a tier, or both type and root_volume_size_gb."
  }
}

variable "public_ports" {
  description = "Ports of the instance machine open to the Internet: the fronts (80, 443) and SSH while mairie360/ansible keeps it public (wireguard_close_public_ssh false). k3s (6443) only goes through the WireGuard tunnel."
  type = object({
    tcp = list(number)
    udp = optional(list(number), [])
  })
  default = { tcp = [22, 80, 443] }
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

variable "cockpit_retention_days" {
  description = "Retention of the instance's Cockpit data sources, in days (MAIR-620)."
  type = object({
    metrics = optional(number, 31)
    traces  = optional(number, 7)
  })
  default = {}
}
