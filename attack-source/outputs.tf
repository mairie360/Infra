output "source_ip" {
  description = "Address the external attack campaigns come from: write it in the announcement."
  value       = scaleway_instance_ip.source.address
}

output "server_id" {
  description = "ID of the attack source server, null outside a campaign window."
  value       = var.enabled ? scaleway_instance_server.source[0].id : null
}
