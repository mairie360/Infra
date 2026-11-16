# Cockpit data sources of the instance (MAIR-620): its OpenTelemetry Collector
# (Deploiment charts/observability) pushes the APIs' traces and the pod
# metrics there, over OTLP/HTTP with the instance's Cockpit token (vault
# secret cockpit-token, issued by scripts/issue-cockpit-tokens.sh: a token
# made here would sit in the state). The push endpoints go into
# observability.cockpit.* of the Deploiment values (output cockpit_endpoints).

resource "scaleway_cockpit_source" "metrics" {
  name           = "${var.org_id}-${var.env_name}-metrics"
  type           = "metrics"
  retention_days = var.cockpit_retention_days.metrics
  project_id     = var.project_id
  region         = var.region

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_cockpit_source" "traces" {
  name           = "${var.org_id}-${var.env_name}-traces"
  type           = "traces"
  retention_days = var.cockpit_retention_days.traces
  project_id     = var.project_id
  region         = var.region

  lifecycle {
    prevent_destroy = true
  }
}
