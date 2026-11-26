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
  description = "Records outside the instances (mail, domain verification, third parties), by a free key. zone defaults to dns_zone; another zone of the project (mairie360.fr) is named explicitly. The n8n machine gets n8n.<zone> on its own, machine_records the names that follow a machine."
  type = map(object({
    name = string
    type = string
    data = string
    ttl  = optional(number, 3600)
    # MX (and SRV) only: Scaleway sends it apart from data.
    priority = optional(number)
    zone     = optional(string)
  }))
  default = {}

  # Anti-spoofing (DMARC, external attack campaigns): a DMARC record enforces a
  # policy and asks for aggregate reports; p=none would let a forged From: through.
  validation {
    condition = alltrue([
      for r in values(var.extra_records) : can(regex("^v=DMARC1;.*\\bp=(quarantine|reject);.*\\brua=mailto:", r.data))
      if r.type == "TXT" && can(regex("^_dmarc(\\.|$)", r.name))
    ])
    error_message = "A DMARC record sets p=quarantine or p=reject and a rua=mailto: report address."
  }

  # Two DMARC (or SPF) records on one name void both.
  validation {
    condition = alltrue([
      for kind, pattern in { dmarc = "^v=DMARC1", spf = "^v=spf1" } : length([
        for r in values(var.extra_records) : "${coalesce(r.zone, "dns_zone")}/${r.name}" if r.type == "TXT" && can(regex(pattern, r.data))
        ]) == length(distinct([
          for r in values(var.extra_records) : "${coalesce(r.zone, "dns_zone")}/${r.name}" if r.type == "TXT" && can(regex(pattern, r.data))
      ]))
    ])
    error_message = "At most one DMARC record and one SPF record per name."
  }
}

variable "machine_records" {
  description = "A records of dns_zone that follow one machine of the group, by record name: an instance env (dev, staging, prod), argocd or n8n. For names outside <host>.<env> (env apex, wildcards, the Argo CD hub), so no address is written here."
  type        = map(string)
  default     = {}
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

variable "resend_receiving_mx" {
  description = "MX target of the Resend receiving inbox on mairie360.fr (spoofed e-mail test of the external attack campaigns), as shown by Resend. null = no inbox."
  type        = string
  default     = null
}
