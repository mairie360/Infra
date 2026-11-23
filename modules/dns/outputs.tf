output "instance_domain" {
  description = "Domain of the instance (instance_domain of Ansible, global.domain of Deploiment)."
  value       = local.instance_domain
}

output "hostnames" {
  description = "Fully qualified name of each host, by host."
  value       = { for host in var.hosts : host => "${host}.${local.instance_domain}" }
}

output "records" {
  description = "The records, by host."
  value       = { for host, r in scaleway_domain_record.host : host => { type = r.type, data = r.data } }
}
