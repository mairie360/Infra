# MAIR-620: the Cockpit data sources of an instance and the endpoints its
# collector pushes to. Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "scaleway_cockpit_source" {
    defaults = {
      push_url = "https://abcd.metrics.cockpit.fr-par.scw.cloud"
      url      = "https://abcd.metrics.cockpit.fr-par.scw.cloud"
    }
  }
}

variables {
  org_id     = "mairie360"
  env_name   = "prod"
  project_id = "00000000-0000-0000-0000-000000000000"
  machine    = { type = "POP2-2C-8G", root_volume_size_gb = 30 }
}

run "metrics_and_traces_sources_per_instance" {
  command = apply

  assert {
    condition     = scaleway_cockpit_source.metrics.type == "metrics" && scaleway_cockpit_source.traces.type == "traces"
    error_message = "One metrics and one traces data source per instance."
  }

  assert {
    condition     = scaleway_cockpit_source.metrics.name == "mairie360-prod-metrics" && scaleway_cockpit_source.traces.name == "mairie360-prod-traces"
    error_message = "Sources are named <org>-<env>-<type>."
  }

  assert {
    condition     = scaleway_cockpit_source.metrics.retention_days == 31 && scaleway_cockpit_source.traces.retention_days == 7
    error_message = "Default retention: 31 days of metrics (backup alert looks 27 h back), 7 of traces."
  }
}

run "otlp_endpoints_for_the_collector" {
  command = apply

  assert {
    condition     = output.cockpit_endpoints.metricsEndpoint == "https://abcd.metrics.cockpit.fr-par.scw.cloud/otlp/v1/metrics"
    error_message = "metricsEndpoint is the push URL + /otlp/v1/metrics, as charts/observability expects."
  }

  assert {
    condition     = endswith(output.cockpit_endpoints.tracesEndpoint, "/otlp/v1/traces")
    error_message = "tracesEndpoint is the push URL + /otlp/v1/traces."
  }
}
