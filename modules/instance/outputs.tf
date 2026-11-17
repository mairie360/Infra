output "vault_path" {
  description = "Path of the instance's secrets in Secret Manager (vault_path of role k8s_instance_secrets)."
  value       = local.vault_path
}

output "vault_secret_ids" {
  description = "Secret Manager id of each vault secret of the instance, by name."
  # The provider's id is <region>/<uuid>; the API takes the uuid.
  value = { for name, secret in scaleway_secret.vault : name => element(split("/", secret.id), length(split("/", secret.id)) - 1) }
}
