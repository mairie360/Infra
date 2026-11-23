variable "org_id" {
  description = "Group id (org_id of the Ansible inventory, prefix of the vault paths)."
  type        = string
  default     = "mairie360"
}

variable "project_id" {
  description = "Scaleway project of the mairie360 group."
  type        = string
}

variable "instances" {
  description = "Instances of the group (key = env_name of the Ansible inventory) and their machine: a tier (small, medium, large, modules/instance) or an explicit type and volume size."
  type = map(object({
    machine = object({
      tier                = optional(string)
      type                = optional(string)
      root_volume_size_gb = optional(number)
      name                = optional(string)
    })
  }))
}

variable "dns_zone" {
  description = "Zone of the group's public names in Scaleway Domains (<host>.<env>.<zone>, modules/dns). null = the names are managed elsewhere (mairie360-eip.fr is still served by o2switch)."
  type        = string
  default     = null
}

variable "extra_records" {
  description = "Records of dns_zone outside the instances (mail, domain verification...), by a free key. The n8n machine gets n8n.<zone> on its own."
  type = map(object({
    name = string
    type = string
    data = string
    ttl  = optional(number, 3600)
    # MX (and SRV) only: Scaleway sends it apart from data.
    priority = optional(number)
  }))
  default = {}
}

variable "argocd_machine" {
  description = "Machine holding the group's Argo CD (Ansible group <org>_argocd)."
  type = object({
    name                = string
    type                = string
    root_volume_size_gb = number
  })
}

variable "n8n_machine" {
  description = "Machine running n8n. Not a k3s machine: Ansible does not manage it. null = the group has none."
  type = object({
    name                = string
    type                = string
    root_volume_size_gb = number
  })
  default = null
}

variable "imported_machines" {
  description = "Machines made before Terraform, by key (an instance env, \"argocd\" or \"n8n\"): ids to import (MAIR-637)."
  type = map(object({
    server_id = string
    ipv4_id   = string
    ipv6_id   = string
    zone      = optional(string, "fr-par-1")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.imported_machines) : k == "argocd" || k == "n8n" || contains(keys(var.instances), k)])
    error_message = "imported_machines keys are \"argocd\", \"n8n\" or an env of var.instances."
  }
}

variable "alert_emails" {
  description = "Addresses every alert of the group is e-mailed to (MAIR-623). A team address, not a person's."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0 && alltrue([for e in var.alert_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$", e))])
    error_message = "At least one e-mail address: an alert nobody receives is no alert."
  }
}

variable "import_alert_manager" {
  description = "Adopt the alert manager already enabled in the console (true for mairie360; a new client project leaves it false)."
  type        = bool
  default     = false
}
