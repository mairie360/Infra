variable "project_id" {
  description = "Scaleway project holding the Terraform state (the mairie360 project)."
  type        = string
}

variable "state_bucket" {
  description = "Bucket of every Terraform state of this repository. Keep in sync with the backend blocks."
  type        = string
  default     = "mairie360-tfstate"
}
