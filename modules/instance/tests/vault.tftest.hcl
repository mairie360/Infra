# MAIR-617: the vault secrets role k8s_instance_secrets looks up. No Scaleway
# account used: the provider is mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  org_id     = "mairie360"
  env_name   = "dev"
  project_id = "00000000-0000-0000-0000-000000000000"
}

run "three_protected_secrets_under_org_env" {
  command = apply

  assert {
    condition     = toset(keys(scaleway_secret.vault)) == toset(["restic-password", "admin-password", "sealing-keys", "resend-api-key", "cockpit-token"])
    error_message = "The role expects exactly restic-password, admin-password, sealing-keys, resend-api-key and cockpit-token."
  }

  assert {
    condition     = alltrue([for s in scaleway_secret.vault : s.path == "/mairie360/dev" && s.protected && s.type == "opaque"])
    error_message = "Every vault secret is opaque, protected and stored under /<org>/<env>."
  }

  assert {
    condition     = alltrue([for s in scaleway_secret.vault : s.project_id == var.project_id && s.region == "fr-par"])
    error_message = "The secrets belong to the group's project, in fr-par."
  }

  assert {
    condition     = output.vault_path == "/mairie360/dev"
    error_message = "vault_path must match the role's default /<org_id>/<env_name>."
  }

  assert {
    condition     = output.vault_secret_ids["sealing-keys"] == "11111111-1111-1111-1111-111111111111"
    error_message = "The ids are output without the region prefix."
  }
}

run "refuses_a_path_the_role_would_not_build" {
  command = plan

  variables {
    env_name = "Prod/eu"
  }

  expect_failures = [var.env_name]
}
