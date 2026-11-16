# External probe of the group (MAIR-621): an OpenTelemetry Collector on the
# group's Argo CD machine (mairie360/ansible role hub_probe) checks every
# instance's public URLs from outside the instances, and pushes the results to
# this metrics data source; the rules of alerts/group/ (pushed by
# scripts/push-alert-rules.sh) e-mail the team through the alert manager
# (alerting.tf) when a site stops answering or the probe itself goes silent.

resource "scaleway_cockpit_source" "probes" {
  name           = "${var.org_id}-probes"
  type           = "metrics"
  retention_days = 31
  project_id     = var.project_id
  region         = "fr-par"

  lifecycle {
    prevent_destroy = true
  }
}

# The probe's push-only Cockpit token, issued by scripts/issue-cockpit-tokens.sh
# (env "hub"), read by role hub_probe: same contract as the instance secrets.
resource "scaleway_secret" "hub_cockpit_token" {
  name        = "cockpit-token"
  path        = "/${var.org_id}/hub"
  description = "Push-only Cockpit token of the external probe on the Argo CD machine (MAIR-621)."
  type        = "opaque"
  protected   = true
  project_id  = var.project_id
  region      = "fr-par"
  tags        = ["mairie360", "org:${var.org_id}", "env:hub", "managed-by:terraform"]

  lifecycle {
    prevent_destroy = true
  }
}
