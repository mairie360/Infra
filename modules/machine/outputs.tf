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
