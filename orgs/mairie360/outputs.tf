output "instances" {
  description = "Per env: vault path and secret ids (read by mairie360/ansible), backup bucket (Deploiment values)."
  value = {
    for env, instance in module.instance : env => {
      vault_path       = instance.vault_path
      vault_secret_ids = instance.vault_secret_ids
      backup_bucket    = instance.backup_bucket
      elearning_bucket = instance.elearning_bucket
    }
  }
}

# MAIR-637: read by scripts/inventory-from-terraform.py of mairie360/ansible,
# which writes the gitignored inventory/hosts.yml. Keys are the Ansible host
# names (<org>-argocd, <org>-<env>); the public addresses never get committed.
output "ansible_hosts" {
  description = "Ansible host name => group role, env and public address of its machine."
  value = merge(
    {
      "${var.org_id}-argocd" = {
        group       = "${replace(var.org_id, "-", "_")}_argocd"
        env_name    = null
        public_ipv4 = module.argocd.public_ipv4
      }
    },
    {
      for env, instance in module.instance : "${var.org_id}-${env}" => {
        group       = "${replace(var.org_id, "-", "_")}_instances"
        env_name    = env
        public_ipv4 = instance.machine.public_ipv4
      }
    },
  )
}
