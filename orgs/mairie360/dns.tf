# Public names of the group: <host>.<env>.<dns_zone> for every instance
# (modules/dns), pointing to the address of its machine, so a new instance needs
# no DNS line. Off while dns_zone is null.

module "dns" {
  source   = "../../modules/dns"
  for_each = var.dns_zone == null ? {} : module.instance

  zone     = var.dns_zone
  env_name = each.key
  address  = each.value.machine.public_ipv4
}

resource "scaleway_domain_record" "n8n" {
  count = var.dns_zone == null || length(module.n8n) == 0 ? 0 : 1

  dns_zone = var.dns_zone
  name     = "n8n"
  type     = "A"
  data     = module.n8n[0].public_ipv4
  ttl      = 300

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_domain_record" "extra" {
  for_each = var.dns_zone == null ? {} : var.extra_records

  dns_zone = var.dns_zone
  name     = each.value.name
  type     = each.value.type
  data     = each.value.data
  ttl      = each.value.ttl

  lifecycle {
    prevent_destroy = true
  }
}
