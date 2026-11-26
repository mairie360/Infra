# MAIR-621: the external probe's data source, token secret and outputs.
mock_provider "scaleway" {
  mock_resource "scaleway_cockpit_source" {
    defaults = {
      # What Scaleway returns: push_url already holds a push path.
      push_url = "https://abcd.metrics.cockpit.fr-par.scw.cloud/api/v1/push"
      url      = "https://abcd.metrics.cockpit.fr-par.scw.cloud"
    }
  }
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  # The public names are tested in mair_1187_dns_mail.tftest.hcl: none here.
  dns_zone             = null
  extra_records        = {}
  machine_records      = {}
  resend_receiving_mx  = null
  imported_machines    = {}
  import_alert_manager = false
}

run "one_probes_source_and_a_protected_hub_token_secret" {
  command = apply

  assert {
    condition     = scaleway_cockpit_source.probes.name == "mairie360-probes" && scaleway_cockpit_source.probes.type == "metrics"
    error_message = "The group's probes push to <org>-probes, a metrics source."
  }

  assert {
    condition     = scaleway_secret.hub_cockpit_token.path == "/mairie360/hub" && scaleway_secret.hub_cockpit_token.name == "cockpit-token"
    error_message = "Role hub_probe of mairie360/ansible reads /<org>/hub/cockpit-token."
  }

  assert {
    condition     = scaleway_secret.hub_cockpit_token.protected
    error_message = "Vault secrets are protected."
  }

  assert {
    condition     = output.probes.metrics_endpoint == "https://abcd.metrics.cockpit.fr-par.scw.cloud/otlp/v1/metrics"
    error_message = "The probe pushes OTLP to the source's push URL."
  }

  assert {
    condition     = alltrue([for env, i in output.instances : i.cockpit_metrics_url != ""])
    error_message = "Each instance exposes its ruler URL (MAIR-622)."
  }
}
