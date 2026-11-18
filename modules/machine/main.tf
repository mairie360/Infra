# One machine of a group: a Scaleway Instance and its public addresses
# (MAIR-637). The machines that already exist were made in the console and are
# imported by the root (import blocks in orgs/<org>/imports.tf), never
# recreated: prevent_destroy everywhere, the image is ignored after the first
# creation (the OS is upgraded in place by mairie360/ansible), and the CI refuses
# a plan that replaces a server (no-destroy job).

resource "scaleway_instance_ip" "v4" {
  type       = "routed_ipv4"
  project_id = var.project_id
  zone       = var.zone

  lifecycle {
    prevent_destroy = true
  }
}

# Every machine also has a routed IPv6: it must be listed in ip_ids, which is
# applied when the machine is created.
resource "scaleway_instance_ip" "v6" {
  type       = "routed_ipv6"
  project_id = var.project_id
  zone       = var.zone

  lifecycle {
    prevent_destroy = true
  }
}

# Public ports of the machine, in front of its ufw (mairie360/ansible opens the
# same ones): inbound dropped by default, stateful (answers and outbound
# connections such as WireGuard to the hub pass), outbound open. Not created
# when public_ports is null: the machine keeps the project's default group.
resource "scaleway_instance_security_group" "this" {
  count = var.public_ports == null ? 0 : 1

  name                    = var.name
  project_id              = var.project_id
  zone                    = var.zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  # Scaleway's SMTP egress block (25, 465, 587): the platform sends e-mail
  # through the Resend HTTPS API.
  enable_default_security = true

  dynamic "inbound_rule" {
    for_each = var.public_ports.tcp
    content {
      action   = "accept"
      protocol = "TCP"
      port     = inbound_rule.value
    }
  }

  dynamic "inbound_rule" {
    for_each = var.public_ports.udp
    content {
      action   = "accept"
      protocol = "UDP"
      port     = inbound_rule.value
    }
  }

  # Path MTU discovery and ping.
  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_instance_server" "this" {
  name       = var.name
  type       = var.type
  image      = var.image
  project_id = var.project_id
  zone       = var.zone
  ip_ids     = [scaleway_instance_ip.v4.id, scaleway_instance_ip.v6.id]
  # Moving a machine to its group is done in place, without a restart.
  security_group_id = var.public_ports == null ? null : scaleway_instance_security_group.this[0].id
  # Sorted: the API returns them sorted.
  tags = sort(var.tags)

  # A type change resizes in place (stop, change, start), never a new machine.
  replace_on_type_change = false

  root_volume {
    volume_type = "sbs_volume"
    size_in_gb  = var.root_volume_size_gb
    sbs_iops    = var.root_volume_iops
  }

  lifecycle {
    prevent_destroy = true
    # Imported machines were installed from an image Terraform did not pick;
    # a new image label must never rebuild a machine. ip_id is the deprecated
    # single-IP form the API still fills. ip_ids is only used when a machine is
    # created: for an imported one the provider reads it back empty, which made
    # every plan propose to "attach" the two addresses already attached. The
    # addresses are their own resources (prevent_destroy) and are never moved
    # from here.
    ignore_changes = [image, ip_id, ip_ids, user_data, cloud_init]
  }
}
