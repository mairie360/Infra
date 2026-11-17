output "state_bucket" {
  description = "Name of the Terraform state bucket."
  value       = scaleway_object_bucket.state.name
}
