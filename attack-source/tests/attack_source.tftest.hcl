# MAIR-1185: the disposable source machine of the external attack campaigns.
# Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_instance_ip" {
    defaults = {
      id      = "fr-par-2/33333333-3333-3333-3333-333333333333"
      address = "192.0.2.20"
    }
  }
  mock_resource "scaleway_instance_security_group" {
    defaults = {
      id = "fr-par-2/55555555-5555-5555-5555-555555555555"
    }
  }
  mock_resource "scaleway_instance_server" {
    defaults = {
      id = "fr-par-2/44444444-4444-4444-4444-444444444444"
    }
  }
}

variables {
  project_id = "00000000-0000-0000-0000-000000000000"
}

run "mair_1185_outside_a_window_only_the_ip_is_kept" {
  command = apply

  assert {
    condition     = length(scaleway_instance_server.source) == 0
    error_message = "Without enabled, no attack source server exists."
  }

  assert {
    condition     = output.source_ip == "192.0.2.20" && output.server_id == null
    error_message = "The reserved IP is published even outside a window; no server id."
  }
}

run "mair_1185_campaign_window_server_behind_the_reserved_ip" {
  command = apply

  variables {
    enabled = true
  }

  assert {
    condition     = length(scaleway_instance_server.source) == 1
    error_message = "With enabled, the attack source server exists."
  }

  assert {
    condition     = length(scaleway_instance_server.source[0].ip_ids) == 1 && one(scaleway_instance_server.source[0].ip_ids) == scaleway_instance_ip.source.id
    error_message = "The server uses the reserved IP and only it."
  }

  assert {
    condition     = length(scaleway_instance_server.source[0].private_network) == 0
    error_message = "The attack source never joins a private network."
  }

  assert {
    condition     = scaleway_instance_server.source[0].zone != "fr-par-1" && scaleway_instance_ip.source.zone == scaleway_instance_server.source[0].zone
    error_message = "The source runs outside the instances' zone, with its IP in its own zone."
  }

  assert {
    condition     = scaleway_instance_server.source[0].security_group_id == scaleway_instance_security_group.source.id
    error_message = "The server is behind the attack source security group."
  }

  assert {
    condition     = output.server_id == "fr-par-2/44444444-4444-4444-4444-444444444444"
    error_message = "The server id is published during a window."
  }
}

run "mair_1185_inbound_dropped_but_ssh" {
  command = apply

  assert {
    condition     = scaleway_instance_security_group.source.inbound_default_policy == "drop" && alltrue([for r in scaleway_instance_security_group.source.inbound_rule : r.port == 22 && r.protocol == "TCP"])
    error_message = "Inbound traffic is dropped except SSH."
  }

  assert {
    condition     = scaleway_instance_security_group.source.enable_default_security
    error_message = "Scaleway's SMTP egress block stays on."
  }
}

run "mair_1185_instances_zone_refused" {
  command = plan

  variables {
    zone = "fr-par-1"
  }

  expect_failures = [var.zone]
}

run "mair_1187_platform_project_refused" {
  command = plan

  variables {
    project_id = "716a44bd-7d6f-4940-87ca-711e62799cd0"
  }

  expect_failures = [var.project_id]
}

run "mair_1187_spoof_test_opens_smtp_and_sends_at_boot" {
  command = apply

  variables {
    enabled    = true
    spoof_test = { to = "spoof-test@mairie360.fr", from = "noreply@mairie360-eip.fr", token = "testtokentesttoken" }
  }

  assert {
    condition     = !scaleway_instance_security_group.source.enable_default_security
    error_message = "The spoofed e-mail test lifts Scaleway's SMTP egress block."
  }

  assert {
    condition = (
      strcontains(scaleway_instance_server.source[0].user_data["cloud-init"], "swaks --to 'spoof-test@mairie360.fr' --from 'noreply@mairie360-eip.fr'")
      && strcontains(scaleway_instance_server.source[0].user_data["cloud-init"], "spoof test testtokentesttoken")
    )
    error_message = "The server sends the spoofed e-mail with its token at first boot."
  }
}

run "mair_1187_no_spoof_test_keeps_smtp_blocked_and_no_user_data" {
  command = apply

  variables {
    enabled = true
  }

  assert {
    condition     = scaleway_instance_security_group.source.enable_default_security && length(scaleway_instance_server.source[0].user_data) == 0
    error_message = "A campaign window without the spoof test keeps SMTP blocked and runs nothing at boot."
  }
}

run "mair_1187_spoof_test_needs_the_server" {
  command = plan

  variables {
    spoof_test = { to = "spoof-test@mairie360.fr", from = "noreply@mairie360-eip.fr", token = "testtokentesttoken" }
  }

  expect_failures = [var.spoof_test]
}

run "mair_1187_spoof_test_only_to_the_resend_inbox" {
  command = plan

  variables {
    enabled    = true
    spoof_test = { to = "someone@gmail.com", from = "noreply@mairie360-eip.fr", token = "testtokentesttoken" }
  }

  expect_failures = [var.spoof_test]
}

run "mair_1187_spoof_test_only_as_a_mairie360_domain" {
  command = plan

  variables {
    enabled    = true
    spoof_test = { to = "spoof-test@mairie360.fr", from = "ceo@example.com", token = "testtokentesttoken" }
  }

  expect_failures = [var.spoof_test]
}
