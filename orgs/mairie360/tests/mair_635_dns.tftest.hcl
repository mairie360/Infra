# MAIR-635: every instance gets <host>.<env>.<zone> records pointing to its own
# machine, the n8n machine n8n.<zone>; nothing while the zone is elsewhere.
# Provider mocked; a mocked provider cannot import (tests/test_imports.py).
variables {
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
  mock_resource "scaleway_instance_security_group" {
    defaults = {
      id = "fr-par-1/55555555-5555-5555-5555-555555555555"
    }
  }
}

run "no_record_while_the_zone_is_elsewhere" {
  command = apply

  assert {
    condition     = length(module.dns) == 0 && length(scaleway_domain_record.n8n) == 0 && output.hostnames == {}
    error_message = "dns_zone null: no record (mairie360-eip.fr is served by o2switch)."
  }
}

run "machines_get_their_public_ports" {
  command = apply

  assert {
    condition     = contains([for r in module.argocd.security_group_rules : r], "UDP/51820") && !contains([for r in module.argocd.security_group_rules : r], "TCP/443")
    error_message = "The Argo CD machine opens SSH and WireGuard, no web port."
  }

  assert {
    condition     = toset(module.instance["prod"].machine_security_group_rules) == toset(["TCP/22", "TCP/80", "TCP/443", "ICMP/0"])
    error_message = "An instance opens SSH and the fronts only."
  }
}

run "names_follow_the_template" {
  command = apply

  variables {
    dns_zone      = "example.test"
    extra_records = { verify = { name = "_verify", type = "TXT", data = "token" } }
  }

  assert {
    condition     = output.hostnames["dev"]["login"] == "login.dev.example.test" && output.hostnames["prod"]["auth"] == "auth.prod.example.test"
    error_message = "A front is <front>.<env>.<zone>, the auth host auth.<env>.<zone>."
  }

  assert {
    condition     = length(output.hostnames["staging"]) == 9
    error_message = "Every Ingress host of an instance (eight fronts and auth) gets a record."
  }

  assert {
    condition     = alltrue([for r in module.dns["prod"].records : r.data == "192.0.2.10" && r.type == "A"])
    error_message = "The records point to the address of the instance's own machine (no address in the tfvars)."
  }

  assert {
    condition     = scaleway_domain_record.n8n[0].name == "n8n" && scaleway_domain_record.extra["verify"].type == "TXT"
    error_message = "n8n.<zone> follows its machine; extra records are created as given."
  }
}
