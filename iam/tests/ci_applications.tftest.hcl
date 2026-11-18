# MAIR-803: the IAM applications of the CI and their rights. No Scaleway
# account used: the provider is mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_iam_application" {
    defaults = {
      id = "22222222-2222-2222-2222-222222222222"
    }
  }
}

variables {
  project_id = "00000000-0000-0000-0000-000000000000"
}

run "three_ci_applications" {
  command = apply

  assert {
    condition     = toset(keys(scaleway_iam_application.ci)) == toset(["ci-terraform-plan", "ci-terraform-apply", "ci-ansible"])
    error_message = "One application per workflow: plan, apply, ansible."
  }

  assert {
    condition     = alltrue([for k, p in scaleway_iam_policy.ci : p.application_id == scaleway_iam_application.ci[k].id])
    error_message = "Each policy belongs to its own application."
  }
}

run "every_rule_is_limited_to_the_project" {
  command = apply

  assert {
    condition = alltrue([
      for p in scaleway_iam_policy.ci : alltrue([
        for r in p.rule : length(r.project_ids) == 1 && one(r.project_ids) == var.project_id
      ])
    ])
    error_message = "Every CI rule is limited to the group's project (organization-wide sets are IAM ones, refused below)."
  }
}

run "no_ci_key_can_manage_iam_or_delete" {
  command = apply

  assert {
    condition = alltrue([
      for p in scaleway_iam_policy.ci : alltrue([
        for r in p.rule : alltrue([
          # ObservabilityFullAccess: Cockpit has no write set below full access (MAIR-620).
          for s in r.permission_set_names : !startswith(s, "IAM") && !endswith(s, "Delete") && (!endswith(s, "FullAccess") || s == "ObservabilityFullAccess")
        ])
      ])
    ])
    error_message = "A CI key never gets IAM rights, a Delete set or a FullAccess set."
  }
}

run "plan_key_is_read_only" {
  command = apply

  assert {
    condition = alltrue([
      for r in scaleway_iam_policy.ci["ci-terraform-plan"].rule : alltrue([
        for s in r.permission_set_names : can(regex("(ReadOnly|Read|List)$", s))
      ])
    ])
    error_message = "The key of pull request plans only reads."
  }
}

run "only_ansible_reads_secret_values" {
  command = apply

  assert {
    condition = toset([
      for k, p in scaleway_iam_policy.ci : k
      if anytrue([for r in p.rule : contains(r.permission_set_names, "SecretManagerSecretAccess")])
    ]) == toset(["ci-ansible"])
    error_message = "Only the Ansible key reads secret values; Terraform never needs them."
  }
}

run "refuses_a_project_that_is_not_a_uuid" {
  command = plan

  variables {
    project_id = "mairie360"
  }

  expect_failures = [var.project_id]
}

# MAIR-637: the apply key manages machines but can never delete one.
run "apply_key_manages_machines_without_delete" {
  command = apply

  assert {
    condition = alltrue([
      for s in ["InstancesServerWrite", "InstancesServerCreate", "InstancesIpWrite"] :
      contains(one(scaleway_iam_policy.ci["ci-terraform-apply"].rule).permission_set_names, s)
    ])
    error_message = "The apply key creates and updates machines and their IPs."
  }

  assert {
    condition = alltrue([
      for s in one(scaleway_iam_policy.ci["ci-terraform-apply"].rule).permission_set_names :
      !startswith(s, "Instances") || !can(regex("(Delete|Snapshot|Image(Create|Write)|SerialConsole)", s))
    ])
    error_message = "No machine, IP or volume deletion, snapshot, image change or console access for the CI."
  }

  assert {
    condition     = contains(one(scaleway_iam_policy.ci["ci-terraform-plan"].rule).permission_set_names, "InstancesReadOnly")
    error_message = "The plan key reads the machines it plans."
  }

  # InstancesReadOnly does not cover the volumes: the first CI plan failed with "insufficient permissions: read volume".
  assert {
    condition     = alltrue([for n in ["InstancesVolumeRead", "InstancesVolumeList"] : contains(one(scaleway_iam_policy.ci["ci-terraform-plan"].rule).permission_set_names, n)])
    error_message = "The plan key reads the volumes of the machines it plans."
  }
}

# MAIR-618: the apply key creates the locked backup buckets, never deletes one.
run "apply_key_creates_buckets_without_delete" {
  command = apply

  assert {
    condition     = contains(one(scaleway_iam_policy.ci["ci-terraform-apply"].rule).permission_set_names, "ObjectStorageBucketsWrite")
    error_message = "The apply key creates buckets and their configuration."
  }

  assert {
    condition     = !contains(one(scaleway_iam_policy.ci["ci-terraform-apply"].rule).permission_set_names, "ObjectStorageBucketsDelete")
    error_message = "No CI key deletes a bucket."
  }
}

# MAIR-620: Cockpit full access is the one exception, for the apply key only.
run "only_the_apply_key_gets_cockpit_full_access" {
  command = apply

  assert {
    condition = alltrue([
      for k, p in scaleway_iam_policy.ci : k == "ci-terraform-apply" || alltrue([
        for r in p.rule : !contains(r.permission_set_names, "ObservabilityFullAccess")
      ])
    ])
    error_message = "Only the approved apply manages Cockpit."
  }
}

# Scaleway IAM only accepts tags matching ^[a-zA-Z0-9._\-/=+@ ]+$ (no ":", unlike the Secret Manager
# ones): the first real apply failed on "managed-by:terraform".
run "iam_tags_follow_the_scaleway_iam_pattern" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for r in concat(values(scaleway_iam_application.ci), values(scaleway_iam_policy.ci), values(scaleway_iam_application.bucket), values(scaleway_iam_policy.bucket)) :
      [for t in r.tags : can(regex("^[a-zA-Z0-9._/=+@ -]+$", t))]
    ]))
    error_message = "An IAM tag only holds letters, digits and . _ - / = + @ and spaces."
  }
}
