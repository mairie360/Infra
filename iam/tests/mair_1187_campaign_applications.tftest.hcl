# MAIR-1187: the applications of the external attack campaigns. Delete rights
# only on the attack project, never on the platform's. Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_iam_application" {
    defaults = {
      id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_resource "scaleway_account_project" {
    defaults = {
      id = "99999999-9999-9999-9999-999999999999"
    }
  }
}

# The mocked applications all share one id: give the spoof test key its own,
# so the bucket policy statements can be told apart.
override_resource {
  target = scaleway_iam_application.campaign["ci-spoof-test"]
  values = {
    id = "77777777-7777-7777-7777-777777777777"
  }
}

variables {
  project_id = "00000000-0000-0000-0000-000000000000"
}

run "two_campaign_applications_in_their_own_project" {
  command = apply

  assert {
    condition     = toset(keys(scaleway_iam_application.campaign)) == toset(["ci-spoof-test", "ci-recon-dns"])
    error_message = "Two campaign applications: the spoofed e-mail test and the DNS reconnaissance."
  }

  assert {
    condition     = scaleway_account_project.attack.name == "mairie360-attack" && output.attack_project_id == "99999999-9999-9999-9999-999999999999"
    error_message = "The attack source gets its own project, exported for attack-source/."
  }
}

run "write_and_delete_only_on_the_attack_project" {
  command = apply

  assert {
    condition = alltrue(flatten([
      for p in scaleway_iam_policy.campaign : [
        for r in p.rule : [
          for s in r.permission_set_names :
          !startswith(s, "IAM") && (
            one(r.project_ids) == scaleway_account_project.attack.id
            || startswith(s, "ObjectStorageObjects") || endswith(s, "Read") || endswith(s, "ReadOnly")
          )
        ]
      ]
    ]))
    error_message = "No IAM right; on the platform's project, only reads and the state objects (bounded by the bucket policy)."
  }

  assert {
    condition = alltrue(flatten([
      for p in scaleway_iam_policy.campaign : [
        for r in p.rule : [
          for s in r.permission_set_names : !endswith(s, "FullAccess") || one(r.project_ids) == scaleway_account_project.attack.id
        ]
      ]
    ]))
    error_message = "Full access sets only on the attack project."
  }

  assert {
    condition = alltrue(flatten([
      for p in scaleway_iam_policy.campaign : [for r in p.rule : contains([var.project_id, scaleway_account_project.attack.id], one(r.project_ids))]
    ]))
    error_message = "Every rule names one project of the group."
  }
}

run "dns_reconnaissance_only_reads_dns" {
  command = apply

  assert {
    condition     = toset(one(scaleway_iam_policy.campaign["ci-recon-dns"].rule).permission_set_names) == toset(["DomainsDNSReadOnly"])
    error_message = "The reconnaissance key reads DNS records and nothing else."
  }
}

run "spoof_test_reaches_only_its_state" {
  command = apply

  assert {
    condition = length([
      for s in jsondecode(scaleway_object_bucket_policy.state.policy).Statement : s
      if s.Principal.SCW == "application_id:${scaleway_iam_application.campaign["ci-spoof-test"].id}"
      && alltrue([for r in s.Resource : contains(["mairie360-tfstate", "mairie360-tfstate/attack-source.tfstate", "mairie360-tfstate/attack-source.tfstate.tflock"], r)])
    ]) == 3
    error_message = "The spoof test key lists the state bucket, reads/writes attack-source.tfstate and its lock, deletes the lock only."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(scaleway_object_bucket_policy.state.policy).Statement :
      !contains(s.Resource, "mairie360-tfstate/*") || s.Principal.SCW != "application_id:${scaleway_iam_application.campaign["ci-spoof-test"].id}"
    ])
    error_message = "The spoof test key never gets the whole state bucket."
  }
}
