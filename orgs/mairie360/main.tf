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
