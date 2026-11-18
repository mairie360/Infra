variable "zone" {
  description = "DNS zone the records live in (the registered domain), e.g. mairie360-eip.fr. It must already exist in Scaleway Domains."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.zone))
    error_message = "zone is a lowercase domain name, e.g. mairie360-eip.fr."
  }
}

variable "env_name" {
  description = "Environment of the instance (env_name of the Ansible inventory). Its domain is <env_name>.<zone>, the instance_domain of the Ansible inventory and global.domain of Deploiment."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.env_name))
    error_message = "env_name is lowercase letters, digits and dashes, like the Ansible env_name."
  }
}

variable "address" {
  description = "Public IPv4 of the instance (ansible_host of the Ansible inventory)."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.address))
    error_message = "address is an IPv4 address."
  }
}

variable "hosts" {
  description = <<-EOT
    Sub-domains of the instance domain that point to the instance. Default: what
    Deploiment exposes. The fronts (templates/ingress.yaml of the chart) are
    <front without "-front">.<domain>, and Keycloak is auth.<domain>
    (mairie360.keycloakHost). Add a name here when a front is added to the chart.
  EOT
  type        = set(string)
  default = [
    "login",
    "project",
    "calendar",
    "message",
    "dashboard",
    "settings",
    "elearning",
    "admin",
    "auth",
  ]
}

variable "ttl" {
  description = "TTL of the records, in seconds."
  type        = number
  default     = 300
}
