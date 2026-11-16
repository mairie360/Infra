# MAIR-619: one key per bucket, each limited to its bucket by the bucket
# policies. Provider mocked.
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

run "one_application_per_instance_bucket" {
  command = apply

  assert {
    condition = toset([for b in output.bucket_keys : b.name]) == toset([
      "mairie360-backups-dev", "mairie360-backups-staging", "mairie360-backups-prod",
      "mairie360-elearning-dev", "mairie360-elearning-staging", "mairie360-elearning-prod",
    ])
    error_message = "Every backup and e-learning bucket of the group has its own application."
  }

  assert {
    condition     = output.bucket_keys["prod/backup"].secret == "/mairie360/prod/backup-s3-key" && output.bucket_keys["dev/elearning"].secret == "/mairie360/dev/elearning-s3-key"
    error_message = "Each key goes to the vault secret role k8s_instance_secrets reads."
  }

  assert {
    condition = alltrue([
      for p in scaleway_iam_policy.bucket : alltrue([
        for r in p.rule : one(r.project_ids) == var.project_id && alltrue([
          for s in r.permission_set_names : startswith(s, "ObjectStorage") && !endswith(s, "FullAccess") && s != "ObjectStorageBucketsWrite" && s != "ObjectStorageBucketsDelete"
        ])
      ])
    ])
    error_message = "A bucket key only handles objects, in the group's project: no bucket creation, deletion or other product."
  }
}

run "bucket_policy_lists_only_its_own_key_for_objects" {
  command = apply

  assert {
    condition = alltrue([
      for k, p in scaleway_object_bucket_policy.instance : alltrue([
        for s in jsondecode(p.policy).Statement :
        s.Sid == "own-key-objects" || s.Sid == "operators" || alltrue([for a in s.Action : !contains(["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:*"], a)])
      ])
    ])
    error_message = "Only the bucket's own key (and the operators) may touch its objects: the CI only reads and writes its configuration."
  }

  assert {
    condition = alltrue([
      for k, p in scaleway_object_bucket_policy.instance :
      one([for s in jsondecode(p.policy).Statement : s if s.Sid == "own-key-objects"]).Principal.SCW == "application_id:${scaleway_iam_application.bucket[k].id}"
    ])
    error_message = "The object statement names the bucket's own application."
  }

  assert {
    condition = alltrue([
      for p in scaleway_object_bucket_policy.instance : alltrue([
        for s in jsondecode(p.policy).Statement : !contains(s.Action, "s3:DeleteObjectVersion")
      ])
    ])
    error_message = "No key deletes an object version: on a versioned bucket a delete only adds a marker."
  }

  assert {
    condition     = alltrue([for p in scaleway_object_bucket_policy.instance : jsondecode(p.policy).Version == "2023-04-17"])
    error_message = "Scaleway's current bucket policy version (allow-only)."
  }
}

run "state_bucket_reachable_by_the_ci_only" {
  command = apply

  assert {
    condition     = scaleway_object_bucket_policy.state.bucket == "mairie360-tfstate"
    error_message = "The Terraform state bucket gets a policy too, or every bucket key could read it."
  }

  assert {
    condition = (
      length(jsondecode(scaleway_object_bucket_policy.state.policy).Statement) == 2
      && !contains(one([for s in jsondecode(scaleway_object_bucket_policy.state.policy).Statement : s if s.Sid == "ci-plan-state"]).Action, "s3:PutObject")
    )
    error_message = "Only the two CI applications reach the state, and the plan key cannot write it."
  }
}

run "operators_keep_access_when_listed" {
  command = apply

  variables {
    operator_user_ids = ["33333333-3333-3333-3333-333333333333"]
  }

  assert {
    condition     = one([for s in jsondecode(scaleway_object_bucket_policy.state.policy).Statement : s if s.Sid == "operators"]).Principal.SCW == ["user_id:33333333-3333-3333-3333-333333333333"]
    error_message = "Listed operators keep full access to the state bucket."
  }
}

run "refuses_an_operator_that_is_not_a_uuid" {
  command = plan

  variables {
    operator_user_ids = ["alice"]
  }

  expect_failures = [var.operator_user_ids]
}
