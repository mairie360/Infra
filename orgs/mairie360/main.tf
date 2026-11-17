# Group mairie360: the platform's own dev, staging and prod instances, and the
# machine holding the group's Argo CD.
# A client group is a copy of this folder (orgs/<org>) with its own project.

module "instance" {
  source   = "../../modules/instance"
  for_each = var.instances

  org_id     = var.org_id
  env_name   = each.key
  project_id = var.project_id
  machine    = each.value.machine
}

# MAIR-637: the group's Argo CD machine (mairie360/ansible group <org>_argocd).
module "argocd" {
  source = "../../modules/machine"

  name                = var.argocd_machine.name
  type                = var.argocd_machine.type
  root_volume_size_gb = var.argocd_machine.root_volume_size_gb
  project_id          = var.project_id
  tags                = [var.org_id, "argocd"]
}

# The machine running n8n, made in the console before this repository and adopted
# (imports.tf). Same module as the others: prevent_destroy, no rebuild on a new image.
# It is not an Ansible host (no k3s, no WireGuard), so it is left out of the
# ansible_hosts output.
module "n8n" {
  source = "../../modules/machine"
  count  = var.n8n_machine == null ? 0 : 1

  name                = var.n8n_machine.name
  type                = var.n8n_machine.type
  root_volume_size_gb = var.n8n_machine.root_volume_size_gb
  project_id          = var.project_id
  tags                = ["n8n"]
}
