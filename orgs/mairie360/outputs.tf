output "instances" {
  description = "Per env: vault path and secret ids, read by mairie360/ansible."
  value = {
    for env, instance in module.instance : env => {
      vault_path       = instance.vault_path
      vault_secret_ids = instance.vault_secret_ids
    }
  }
}
