# Public names of one instance: <host>.<env>.<zone> -> the instance's IPv4.
#
# Template of the platform's naming: the instance domain is <env>.<zone>, each
# front and Keycloak is one sub-domain of it. This is the DNS record each
# Ingress host of Deploiment needs ("DNS record required" in its values); the
# certificates are issued per host once the name resolves.

locals {
  instance_domain = "${var.env_name}.${var.zone}"
}

resource "scaleway_domain_record" "host" {
  for_each = var.hosts

  dns_zone = var.zone
  name     = "${each.key}.${var.env_name}"
  type     = "A"
  data     = var.address
  ttl      = var.ttl

  lifecycle {
    prevent_destroy = true
  }
}
