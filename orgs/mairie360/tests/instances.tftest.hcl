# Group mairie360 has the vault of its three instances. Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
}

run "vault_of_dev_staging_prod" {
  command = apply

  assert {
    condition     = toset(keys(output.instances)) == toset(["dev", "staging", "prod"])
    error_message = "mairie360 has dev, staging and prod."
  }

  assert {
    condition     = output.instances["prod"].vault_path == "/mairie360/prod"
    error_message = "The vault path is /mairie360/<env>, as role k8s_instance_secrets builds it."
  }

  assert {
    condition     = length(output.instances["staging"].vault_secret_ids) == 5
    error_message = "Each instance has its five vault secrets."
  }
}
