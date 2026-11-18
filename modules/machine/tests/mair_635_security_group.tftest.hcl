# MAIR-635: the public ports of a machine are its security group: inbound dropped
# by default, only the listed ports open, k3s never public. Provider mocked.
mock_provider "scaleway" {
  mock_resource "scaleway_instance_ip" {
    defaults = {
      id      = "fr-par-1/33333333-3333-3333-3333-333333333333"
      address = "192.0.2.10"
      prefix  = "2001:db8::/64"
    }
  }
  mock_resource "scaleway_instance_server" {
    defaults = {
      id = "fr-par-1/44444444-4444-4444-4444-444444444444"
    }
  }
  mock_resource "scaleway_instance_security_group" {
    defaults = {
      id = "fr-par-1/55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  name                = "mairie360-prod"
  type                = "POP2-2C-8G"
  root_volume_size_gb = 30
  project_id          = "00000000-0000-0000-0000-000000000000"
  public_ports        = { tcp = [22, 80, 443] }
}

run "no_ports_keeps_the_default_group" {
  command = apply

  variables {
    public_ports = null
  }

  assert {
    condition     = length(scaleway_instance_security_group.this) == 0 && output.security_group_id == null
    error_message = "Without public_ports the machine keeps the project's default group."
  }
}

run "only_the_listed_ports_are_open" {
  command = apply

  assert {
    condition     = scaleway_instance_security_group.this[0].inbound_default_policy == "drop" && scaleway_instance_security_group.this[0].stateful
    error_message = "Inbound is dropped by default; stateful, so answers and outbound connections pass."
  }

  assert {
    condition     = toset([for r in output.security_group_rules : r if r != "ICMP/0"]) == toset(["TCP/22", "TCP/80", "TCP/443"])
    error_message = "Exactly the listed TCP ports are open."
  }

  assert {
    condition     = scaleway_instance_server.this.security_group_id == "fr-par-1/55555555-5555-5555-5555-555555555555"
    error_message = "The machine is attached to its own group."
  }
}

run "the_wireguard_hub_opens_its_udp_port" {
  command = apply

  variables {
    public_ports = { tcp = [22], udp = [51820] }
  }

  assert {
    condition     = contains(output.security_group_rules, "UDP/51820")
    error_message = "The hub accepts the WireGuard tunnels of the instances."
  }
}

run "k3s_is_never_public" {
  command = plan

  variables {
    public_ports = { tcp = [22, 443, 6443] }
  }

  expect_failures = [var.public_ports]
}
