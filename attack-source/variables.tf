variable "project_id" {
  description = "Scaleway project of the mairie360 group."
  type        = string
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
