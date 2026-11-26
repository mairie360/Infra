# MAIR-1187: mairie360-eip.fr in Scaleway Domains, anti-spoofing records of both
# domains, Resend receiving inbox. Reads the real terraform.tfvars.
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

run "zone_records_of_the_tfvars" {
  command = apply

  assert {
    condition     = var.dns_zone == "mairie360-eip.fr" && scaleway_domain_record.machine["*.staging"].data == "192.0.2.10" && scaleway_domain_record.machine["argocd-hub"].name == "argocd-hub"
    error_message = "mairie360-eip.fr is managed here; env apexes, wildcards and the Argo CD hub follow their machine."
  }

  assert {
    condition = alltrue([
      for r in scaleway_domain_record.extra : can(regex("p=(quarantine|reject);", r.data)) && strcontains(r.data, "rua=mailto:dmarc@mairie360.fr")
      if r.name == "_dmarc"
    ]) && length([for r in scaleway_domain_record.extra : r if r.name == "_dmarc"]) == 2
    error_message = "Both domains enforce DMARC and send their reports to the Resend inbox."
  }

  assert {
    condition     = scaleway_domain_record.extra["fr_spf"].dns_zone == "mairie360.fr" && scaleway_domain_record.extra["fr_spf"].data == "v=spf1 -all"
    error_message = "mairie360.fr authorises no sending server of its own (Resend signs with DKIM, its envelope is send.mairie360.fr)."
  }

  assert {
    condition     = scaleway_domain_record.extra["fr_dmarc_reports"].name == "mairie360-eip.fr._report._dmarc" && scaleway_domain_record.extra["fr_dmarc_reports"].data == "v=DMARC1"
    error_message = "mairie360.fr accepts the DMARC reports of mairie360-eip.fr."
  }

  assert {
    condition     = scaleway_domain_record.extra["mx"].priority == 0 && scaleway_domain_record.extra["dkim_resend"].name == "resend._domainkey"
    error_message = "The team mailbox (o2switch MX) and Resend's signature move with the zone."
  }
}

run "resend_inbox_on_mairie360_fr" {
  state_key = "resend_inbox_on_mairie360_fr"
  command   = apply

  variables {
    resend_receiving_mx = "receive.example.test."
  }

  assert {
    condition     = scaleway_domain_record.resend_receiving[0].dns_zone == "mairie360.fr" && scaleway_domain_record.resend_receiving[0].type == "MX"
    error_message = "The spoofed e-mail test inbox is the MX of mairie360.fr, pointing to Resend."
  }
}

run "dmarc_none_refused" {
  state_key = "dmarc_none_refused"
  command   = plan

  variables {
    extra_records = { dmarc = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=none; rua=mailto:dmarc@mairie360.fr" } }
  }

  expect_failures = [var.extra_records]
}

run "dmarc_without_reports_refused" {
  state_key = "dmarc_without_reports_refused"
  command   = plan

  variables {
    extra_records = { dmarc = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=reject;" } }
  }

  expect_failures = [var.extra_records]
}

run "two_dmarc_records_on_one_name_refused" {
  state_key = "two_dmarc_records_on_one_name_refused"
  command   = plan

  variables {
    extra_records = {
      a = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=reject; rua=mailto:dmarc@mairie360.fr" }
      b = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=quarantine; rua=mailto:dmarc@mairie360.fr" }
    }
  }

  expect_failures = [var.extra_records]
}

run "same_name_in_two_zones_allowed" {
  state_key = "same_name_in_two_zones_allowed"
  command   = plan

  variables {
    extra_records = {
      a = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=reject; rua=mailto:dmarc@mairie360.fr" }
      b = { zone = "mairie360.fr", name = "_dmarc", type = "TXT", data = "v=DMARC1; p=reject; rua=mailto:dmarc@mairie360.fr" }
    }
  }
}
