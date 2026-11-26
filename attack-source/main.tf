# Source machine of the external attack campaigns (mairie360/Deploiment
# docs/en/external-attack-campaigns.md): a server outside every instance's zone
# and private network, created for a campaign window and destroyed after it,
# behind a reserved IP that stays the same from one campaign to the next so
# the announcements and Scaleway can name it.
#
# Lives in its own project (mairie360-attack, iam/campaigns.tf). Applied and
# destroyed from a workstation for a campaign window (scripts/tf.sh attack-source
# apply, with a team member's approval), and by the monthly spoofed e-mail test
# (.github/workflows/spoof-test.yml), whose key only reaches this project.

resource "scaleway_instance_ip" "source" {
  type       = "routed_ipv4"
  project_id = var.project_id
  zone       = var.zone
  tags       = ["mairie360", "attack-source"]

  lifecycle {
    prevent_destroy = true
  }
}

# Inbound dropped but SSH; outbound open (the scenarios reach staging over
# HTTPS), SMTP egress blocked by Scaleway's default security except during the
# spoofed e-mail test.
resource "scaleway_instance_security_group" "source" {
  name                    = "mairie360-attack-source"
  project_id              = var.project_id
  zone                    = var.zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  enable_default_security = var.spoof_test == null

  dynamic "inbound_rule" {
    for_each = var.ssh_ranges
    content {
      action   = "accept"
      protocol = "TCP"
      port     = 22
      ip_range = inbound_rule.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The only resource of the repository without prevent_destroy: it is meant to
# be destroyed after every campaign (enabled = false). Exempted by name in
# tests/check_prevent_destroy.py. No private_network block: it never joins the
# instances' network.
resource "scaleway_instance_server" "source" {
  count = var.enabled ? 1 : 0

  name              = "mairie360-attack-source"
  type              = var.type
  image             = var.image
  project_id        = var.project_id
  zone              = var.zone
  ip_ids            = [scaleway_instance_ip.source.id]
  security_group_id = scaleway_instance_security_group.source.id
  tags              = ["attack-source", "mairie360"]

  # The spoofed e-mail test sends its one message at first boot, no SSH needed.
  user_data = var.spoof_test == null ? {} : {
    cloud-init = templatefile("${path.module}/spoof-test.cloud-init.yaml", var.spoof_test)
  }

  root_volume {
    volume_type = "sbs_volume"
    size_in_gb  = 20
  }
}
