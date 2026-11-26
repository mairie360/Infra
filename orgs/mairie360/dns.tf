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

locals {
  machine_addresses = merge(
    { for env, i in module.instance : env => i.machine.public_ipv4 },
    { argocd = module.argocd.public_ipv4 },
    length(module.n8n) == 0 ? {} : { n8n = module.n8n[0].public_ipv4 },
  )
}

resource "scaleway_domain_record" "machine" {
  for_each = var.dns_zone == null ? {} : var.machine_records

  dns_zone = var.dns_zone
  name     = each.key
  type     = "A"
  data     = local.machine_addresses[each.value]
  ttl      = 300

  lifecycle {
    prevent_destroy = true
  }
}

# Records of dns_zone, or of the zone they name (mairie360.fr), even while
# dns_zone is elsewhere.
resource "scaleway_domain_record" "extra" {
  for_each = { for k, r in var.extra_records : k => r if r.zone != null || var.dns_zone != null }

  dns_zone = coalesce(each.value.zone, var.dns_zone)
  name     = each.value.name
  type     = each.value.type
  data     = each.value.data
  ttl      = each.value.ttl
  priority = each.value.priority

  lifecycle {
    prevent_destroy = true
  }
}

# Inbox of the spoofed e-mail test (attack-source/, spoof-test.yml): every
# message to @mairie360.fr lands in Resend, read through its API. mairie360.fr
# has no other mailbox.
resource "scaleway_domain_record" "resend_receiving" {
  count = var.resend_receiving_mx == null ? 0 : 1

  dns_zone = "mairie360.fr"
  name     = ""
  type     = "MX"
  data     = var.resend_receiving_mx
  priority = 10
  ttl      = 3600

  lifecycle {
    prevent_destroy = true
  }
}
