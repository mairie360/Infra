output "server_id" {
  description = "Id of the server, without the zone prefix."
  value       = element(split("/", scaleway_instance_server.this.id), length(split("/", scaleway_instance_server.this.id)) - 1)
}

output "public_ipv4" {
  description = "Public IPv4 address: ansible_host of the Ansible inventory (never committed)."
  value       = scaleway_instance_ip.v4.address
}

output "public_ipv6" {
  description = "Public IPv6 prefix of the machine."
  value       = scaleway_instance_ip.v6.prefix
}

output "security_group_id" {
  description = "Security group of the machine, null when it keeps the project's default one."
  value       = var.public_ports == null ? null : scaleway_instance_security_group.this[0].id
}

output "type_in_use" {
  description = "Commercial type of the machine."
  value       = var.type
}

output "root_volume_size_gb_in_use" {
  description = "Size of the root volume (GB)."
  value       = var.root_volume_size_gb
}

output "security_group_rules" {
  description = "Open inbound rules as <protocol>/<port>, empty without a group."
  value       = var.public_ports == null ? [] : [for r in scaleway_instance_security_group.this[0].inbound_rule : "${r.protocol}/${r.port == null ? 0 : r.port}"]
}
