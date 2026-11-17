# MAIR-637: the machines made in the Scaleway console before this repository,
# adopted as they are. An import block is a no-op once the resource is in the
# state, so they stay: a fresh state (or a client copy of this folder without
# `imported_machines`) would otherwise create new machines.
# Ids: scw instance server get <id>, scw instance ip list (not secret).

locals {
  # "argocd", "n8n" or an instance env => the module holding its machine.
  imported = var.imported_machines
}

import {
  for_each = { for k, m in local.imported : k => m if k != "argocd" && k != "n8n" }
  to       = module.instance[each.key].module.machine.scaleway_instance_server.this
  id       = "${each.value.zone}/${each.value.server_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k != "argocd" && k != "n8n" }
  to       = module.instance[each.key].module.machine.scaleway_instance_ip.v4
  id       = "${each.value.zone}/${each.value.ipv4_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k != "argocd" && k != "n8n" }
  to       = module.instance[each.key].module.machine.scaleway_instance_ip.v6
  id       = "${each.value.zone}/${each.value.ipv6_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "argocd" }
  to       = module.argocd.scaleway_instance_server.this
  id       = "${each.value.zone}/${each.value.server_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "argocd" }
  to       = module.argocd.scaleway_instance_ip.v4
  id       = "${each.value.zone}/${each.value.ipv4_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "argocd" }
  to       = module.argocd.scaleway_instance_ip.v6
  id       = "${each.value.zone}/${each.value.ipv6_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "n8n" }
  to       = module.n8n[0].scaleway_instance_server.this
  id       = "${each.value.zone}/${each.value.server_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "n8n" }
  to       = module.n8n[0].scaleway_instance_ip.v4
  id       = "${each.value.zone}/${each.value.ipv4_id}"
}

import {
  for_each = { for k, m in local.imported : k => m if k == "n8n" }
  to       = module.n8n[0].scaleway_instance_ip.v6
  id       = "${each.value.zone}/${each.value.ipv6_id}"
}
