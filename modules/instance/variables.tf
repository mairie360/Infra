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
