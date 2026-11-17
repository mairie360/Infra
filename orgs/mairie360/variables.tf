variable "project_id" {
  description = "Scaleway project of the mairie360 group."
  type        = string
}

variable "envs" {
  description = "Instances of the group (env_name of the Ansible inventory)."
  type        = set(string)
  default     = ["dev", "staging", "prod"]
}
