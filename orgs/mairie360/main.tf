# Group mairie360: the platform's own dev, staging and prod instances.
# A client group is a copy of this folder (orgs/<org>) with its own project.

module "instance" {
  source   = "../../modules/instance"
  for_each = var.envs

  org_id     = "mairie360"
  env_name   = each.key
  project_id = var.project_id
}
