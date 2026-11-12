# IAM applications of the CI (MAIR-803). Applied from a workstation only, like
# bootstrap/: the CI keys cannot manage IAM, so a workflow can never widen its
# own rights. No API key is created here (it would sit in the state): the
# operator creates one per application with the scw CLI and stores it as a
# GitHub environment secret (README, "CI credentials").
#
# Every rule is limited to the group's project and to what the workflow does:
#   ci-terraform-plan   read the state and the resources (pull request plans);
#   ci-terraform-apply  write the state, create and update secrets (no delete:
#                       the secrets are protected anyway);
#   ci-ansible          role k8s_instance_secrets: find the secrets, read,
#                       add and disable versions (no delete).

locals {
  ci_applications = {
    ci-terraform-plan = {
      description     = "terraform plan of mairie360/Infra pull requests: read-only."
      permission_sets = ["ObjectStorageReadOnly", "SecretManagerReadOnly"]
    }
    ci-terraform-apply = {
      description = "terraform apply of mairie360/Infra (approved workflow on main)."
      permission_sets = [
        "ObjectStorageBucketsRead",
        "ObjectStorageObjectsRead",
        "ObjectStorageObjectsWrite",
        "SecretManagerReadOnly",
        "SecretManagerSecretCreate",
        "SecretManagerSecretWrite",
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
  tags        = ["mairie360", "ci", "managed-by:terraform"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_iam_policy" "ci" {
  for_each = local.ci_applications

  name           = "mairie360-${each.key}"
  description    = each.value.description
  application_id = scaleway_iam_application.ci[each.key].id
  tags           = ["mairie360", "ci", "managed-by:terraform"]

  rule {
    project_ids          = [var.project_id]
    permission_set_names = each.value.permission_sets
  }

  lifecycle {
    prevent_destroy = true
  }
}
