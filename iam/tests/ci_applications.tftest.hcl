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
          for s in r.permission_set_names : !startswith(s, "IAM") && !endswith(s, "Delete") && !endswith(s, "FullAccess")
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
        for s in r.permission_set_names : endswith(s, "ReadOnly")
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
