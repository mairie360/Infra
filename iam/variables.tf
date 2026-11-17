variable "project_id" {
  description = "Scaleway project the CI applications may act on (the mairie360 group's)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.project_id))
    error_message = "project_id is a Scaleway project UUID."
  }
}

variable "org_id" {
  description = "Group whose instance buckets get one key each (MAIR-619)."
  type        = string
  default     = "mairie360"
}

variable "envs" {
  description = "Instances of the group, as in orgs/<org>/terraform.tfvars."
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

variable "state_bucket" {
  description = "Terraform state bucket of bootstrap/."
  type        = string
  default     = "mairie360-tfstate"
}

variable "operator_user_ids" {
  description = "IAM users (scw iam user list) keeping full access to every bucket besides the organization owner. A user who applies with their own key and is not listed here, nor the owner, loses the state bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.operator_user_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "operator_user_ids are IAM user UUIDs."
  }
}
