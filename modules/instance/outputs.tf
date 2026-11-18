output "vault_path" {
  description = "Path of the instance's secrets in Secret Manager (vault_path of role k8s_instance_secrets)."
  value       = local.vault_path
}

output "vault_secret_ids" {
  description = "Secret Manager id of each vault secret of the instance, by name."
  # The provider's id is <region>/<uuid>; the API takes the uuid.
  value = { for name, secret in scaleway_secret.vault : name => element(split("/", secret.id), length(split("/", secret.id)) - 1) }
}

output "machine" {
  description = "Server id and public addresses of the instance's machine."
  value = {
    server_id   = module.machine.server_id
    public_ipv4 = module.machine.public_ipv4
    public_ipv6 = module.machine.public_ipv6
  }
}

output "backup_bucket" {
  description = "Name of the locked backup bucket (backup.s3.bucket of the Deploiment values)."
  value       = scaleway_object_bucket.backup.name
}

output "elearning_bucket" {
  description = "Name of the e-learning bucket (S3_BUCKET of elearning-api)."
  value       = scaleway_object_bucket.elearning.name
}

output "cockpit_endpoints" {
  description = "OTLP push URLs of the instance's Cockpit data sources (observability.cockpit.* of the Deploiment values)."
  value = {
    metricsEndpoint = "${trimsuffix(scaleway_cockpit_source.metrics.push_url, "/")}/otlp/v1/metrics"
    tracesEndpoint  = "${trimsuffix(scaleway_cockpit_source.traces.push_url, "/")}/otlp/v1/traces"
  }
}

output "cockpit_metrics_url" {
  description = "Base URL of the metrics data source (Prometheus API, ruler of the alert rules)."
  value       = scaleway_cockpit_source.metrics.url
}

output "machine_security_group_rules" {
  description = "Inbound rules open on the instance machine, as <protocol>/<port>."
  value       = module.machine.security_group_rules
}
