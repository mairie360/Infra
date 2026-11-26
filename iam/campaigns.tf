# External attack campaigns (mairie360/Deploiment docs/en/external-attack-campaigns.md).
#
# The attack source (attack-source/) lives in a project of its own: the monthly
# spoofed e-mail test creates and destroys its server from the CI, which needs
# Instances and Block Storage rights with delete. Given on this project only,
# they can never reach a machine of the platform. The state stays in
# mairie360-tfstate, where the bucket policy (buckets.tf) limits the key to the
# objects of attack-source.tfstate.
#
#   ci-spoof-test  attack project: full Instances and Block Storage (create the
#                  source, open its SMTP egress, destroy it); main project:
#                  read and write objects of the state bucket (bucket policy).
#   ci-recon-dns   main project: read the DNS zones (monthly reconnaissance of
#                  mairie360/Deploiment lists every record and checks its target).
#
# Like the CI applications of main.tf, no API key is created here: the operator
# creates one per application with the scw CLI and stores it as a GitHub
# environment secret (README, "CI credentials").

resource "scaleway_account_project" "attack" {
  name        = "mairie360-attack"
  description = "Disposable source of the external attack campaigns (Infra attack-source/). Nothing of the platform."

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  campaign_applications = {
    ci-spoof-test = {
      description = "Monthly spoofed e-mail test of mairie360/Infra: creates and destroys the attack source in mairie360-attack."
      rules = [
        { project = "attack", permission_sets = ["InstancesFullAccess", "BlockStorageFullAccess"] },
        { project = "main", permission_sets = ["ObjectStorageBucketsRead", "ObjectStorageObjectsRead", "ObjectStorageObjectsWrite", "ObjectStorageObjectsDelete"] },
      ]
    }
    ci-recon-dns = {
      description = "Monthly external reconnaissance of mairie360/Deploiment: reads the DNS zones."
      rules = [
        { project = "main", permission_sets = ["DomainsDNSReadOnly"] },
      ]
    }
  }
  campaign_projects = {
    attack = scaleway_account_project.attack.id
    main   = var.project_id
  }
  ci_spoof = "application_id:${scaleway_iam_application.campaign["ci-spoof-test"].id}"
}

resource "scaleway_iam_application" "campaign" {
  for_each = local.campaign_applications

  name        = "mairie360-${each.key}"
  description = each.value.description
  tags        = ["mairie360", "ci", "attack-campaign", "managed-by=terraform"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "campaign" {
  for_each = local.campaign_applications

  name           = "mairie360-${each.key}"
  description    = each.value.description
  application_id = scaleway_iam_application.campaign[each.key].id
  tags           = ["mairie360", "ci", "attack-campaign", "managed-by=terraform"]

  dynamic "rule" {
    for_each = each.value.rules
    content {
      project_ids          = [local.campaign_projects[rule.value.project]]
      permission_set_names = rule.value.permission_sets
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
