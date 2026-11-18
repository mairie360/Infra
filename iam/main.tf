# IAM applications of the CI (MAIR-803). Applied from a workstation only, like
# bootstrap/: the CI keys cannot manage IAM, so a workflow can never widen its
# own rights. No API key is created here (it would sit in the state): the
# operator creates one per application with the scw CLI and stores it as a
# GitHub environment secret (README, "CI credentials").
#
# Every rule is limited to the group's project and to what the workflow does:
#   ci-terraform-plan   read the state and the resources (pull request plans);
#   ci-terraform-apply  write the state, create and update secrets (no delete:
#                       the secrets are protected anyway), create and update
#                       machines and their IPs (MAIR-637; no delete, no
#                       snapshot or image), create and configure buckets
#                       (no bucket delete; objects: the state lock only);
#   ci-ansible          role k8s_instance_secrets: find the secrets, read,
#                       add and disable versions (no delete).

locals {
  ci_applications = {
    ci-terraform-plan = {
      description     = "terraform plan of mairie360/Infra pull requests: read-only."
      permission_sets = ["ObjectStorageReadOnly", "SecretManagerReadOnly", "InstancesReadOnly", "BlockStorageReadOnly", "ObservabilityReadOnly"]
    }
    ci-terraform-apply = {
      description = "terraform apply of mairie360/Infra (approved workflow on main)."
      permission_sets = [
        "ObjectStorageBucketsRead",
        # MAIR-618: create the backup buckets, their versioning and lifecycle
        # (the object lock configuration is under ObjectStorageObjectsWrite).
        "ObjectStorageBucketsWrite",
        "ObjectStorageObjectsRead",
        "ObjectStorageObjectsWrite",
        # Release of the state lock (<key>.tflock). Bucket policies bound it:
        # on the state bucket the .tflock objects only, nothing on the others.
        "ObjectStorageObjectsDelete",
        "SecretManagerReadOnly",
        "SecretManagerSecretCreate",
        "SecretManagerSecretWrite",
        # MAIR-637: machines of modules/machine (imported, then managed).
        "InstancesServerRead",
        "InstancesServerList",
        "InstancesServerCreate",
        "InstancesServerWrite",
        "InstancesIpRead",
        "InstancesIpCreate",
        "InstancesIpWrite",
        "InstancesVolumeRead",
        "InstancesVolumeList",
        "InstancesVolumeCreate",
        # The machines' system volumes are Block Storage volumes, read on every refresh
        # (the first CI plan failed with "read volume").
        "BlockStorageReadOnly",
        "InstancesImageRead",
        "InstancesSecurityGroupRead",
        "InstancesSecurityGroupList",
        # Security group of each machine (public ports, modules/machine).
        "InstancesSecurityGroupCreate",
        "InstancesSecurityGroupWrite",
        # MAIR-620/623: Cockpit data sources, alert manager, alert rules.
        # Cockpit has no finer set than read-only / full access.
        "ObservabilityFullAccess",
      ]
    }
    ci-ansible = {
      description = "playbooks of mairie360/ansible run by the ops runners: vault of the instances."
      permission_sets = [
        "SecretManagerReadOnly",
        "SecretManagerSecretAccess",
        "SecretManagerSecretCreate",
        "SecretManagerSecretWrite",
      ]
    }
  }
}

resource "scaleway_iam_application" "ci" {
  for_each = local.ci_applications

  name        = "mairie360-${each.key}"
  description = each.value.description
  tags        = ["mairie360", "ci", "managed-by=terraform"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "ci" {
  for_each = local.ci_applications

  name           = "mairie360-${each.key}"
  description    = each.value.description
  application_id = scaleway_iam_application.ci[each.key].id
  tags           = ["mairie360", "ci", "managed-by=terraform"]

  rule {
    project_ids          = [var.project_id]
    permission_set_names = each.value.permission_sets
  }

  lifecycle {
    prevent_destroy = true
  }
}
