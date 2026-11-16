variable "name" {
  description = "Scaleway name of the server (the existing ones keep their console name)."
  type        = string
}

variable "type" {
  description = "Commercial type, e.g. POP2-2C-8G."
  type        = string
}

variable "image" {
  description = "Image of a NEW machine only (ignored once created): Ubuntu 26.04, as the existing machines."
  type        = string
  default     = "ubuntu_resolute"
}

variable "root_volume_size_gb" {
  description = "Size of the root Block Storage volume (GB). Can only grow."
  type        = number
}

variable "root_volume_iops" {
  description = "IOPS of the root Block Storage volume (5000 or 15000)."
  type        = number
  default     = 5000

  validation {
    condition     = contains([5000, 15000], var.root_volume_iops)
    error_message = "Block Storage volumes are 5000 or 15000 IOPS."
  }
}

variable "project_id" {
  description = "Scaleway project of the group."
  type        = string
}

variable "zone" {
  description = "Availability zone of the machine."
  type        = string
  default     = "fr-par-1"
}

variable "tags" {
  description = "Tags of the server (the existing ones: org and env, or org and \"argocd\")."
  type        = list(string)
  default     = []
}
