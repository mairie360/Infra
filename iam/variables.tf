variable "project_id" {
  description = "Scaleway project the CI applications may act on (the mairie360 group's)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.project_id))
    error_message = "project_id is a Scaleway project UUID."
  }
}
