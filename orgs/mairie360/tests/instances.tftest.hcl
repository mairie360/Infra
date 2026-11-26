# Group mairie360: vault and machine of its three instances, and its Argo CD
# machine. Provider mocked; a mocked provider cannot import, so the runs drop
# imported_machines (the import list itself is checked by tests/test_imports.py).
variables {
  # The public names are tested in mair_1187_dns_mail.tftest.hcl: none here.
  dns_zone             = null
  extra_records        = {}
  machine_records      = {}
  resend_receiving_mx  = null
  imported_machines    = {}
  import_alert_manager = false
}

mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "scaleway_instance_ip" {
    defaults = {
      id      = "fr-par-1/33333333-3333-3333-3333-333333333333"
      address = "192.0.2.10"
    }
  }
  mock_resource "scaleway_instance_server" {
    defaults = {
      id = "fr-par-1/44444444-4444-4444-4444-444444444444"
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
    condition     = length(output.instances["staging"].vault_secret_ids) == 7
    error_message = "Each instance has its seven vault secrets."
  }
}

# MAIR-637: what scripts/inventory-from-terraform.py of mairie360/ansible reads.
run "ansible_hosts_match_the_inventory_names" {
  command = apply

  assert {
    condition     = toset(keys(output.ansible_hosts)) == toset(["mairie360-argocd", "mairie360-dev", "mairie360-staging", "mairie360-prod"])
    error_message = "Host names are those of the Ansible inventory: <org>-argocd and <org>-<env>."
  }

  assert {
    condition     = output.ansible_hosts["mairie360-argocd"].group == "mairie360_argocd" && output.ansible_hosts["mairie360-prod"].group == "mairie360_instances"
    error_message = "Groups are <org>_argocd and <org>_instances."
  }

  assert {
    condition     = output.ansible_hosts["mairie360-staging"].env_name == "staging" && output.ansible_hosts["mairie360-dev"].public_ipv4 == "192.0.2.10"
    error_message = "Each instance host carries its env_name and its public IPv4."
  }
}

run "refuses_an_import_for_an_unknown_env" {
  command = plan

  variables {
    imported_machines = {
      preprod = { server_id = "x", ipv4_id = "y", ipv6_id = "z" }
    }
  }

  expect_failures = [var.imported_machines]
}

# MAIR-1075: the n8n machine is imported under its own key, which is not an env.
run "accepts_the_n8n_import_key" {
  command = plan

  variables {
    imported_machines = {
      n8n = { server_id = "x", ipv4_id = "y", ipv6_id = "z" }
    }
  }
}

# MAIR-623: every alert is e-mailed to the team.
run "alerts_go_to_the_team_mailbox" {
  command = apply

  assert {
    condition     = [for c in scaleway_cockpit_alert_manager.this.contact_points : c.email] == ["mairie360@gmail.com"]
    error_message = "The alert manager e-mails the team address."
  }
}

run "refuses_an_alert_channel_without_recipient" {
  command = plan

  variables {
    alert_emails = []
  }

  expect_failures = [var.alert_emails]
}

# The n8n machine is a machine of the group, never an Ansible host.
run "n8n_machine_is_managed_but_not_an_ansible_host" {
  command = apply

  assert {
    condition     = output.n8n_machine != null
    error_message = "The n8n machine is declared in terraform.tfvars."
  }

  assert {
    condition     = !contains(keys(output.ansible_hosts), "mairie360-n8n") && length(output.ansible_hosts) == 4
    error_message = "n8n is not a k3s machine: it must not appear in ansible_hosts (inventory-from-terraform.py compares the host lists)."
  }
}
