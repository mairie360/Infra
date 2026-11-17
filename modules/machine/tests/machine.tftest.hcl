# MAIR-637: a machine and its addresses, never recreated. Provider mocked.
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
}

variables {
  name                = "mairie360-dev"
  type                = "POP2-2C-8G"
  root_volume_size_gb = 30
  project_id          = "00000000-0000-0000-0000-000000000000"
  tags                = ["mairie360", "dev"]
}

run "server_keeps_both_routed_ips" {
  command = apply

  assert {
    condition     = scaleway_instance_ip.v4.type == "routed_ipv4" && scaleway_instance_ip.v6.type == "routed_ipv6"
    error_message = "Each machine has one routed IPv4 and one routed IPv6."
  }

  assert {
    condition     = length(scaleway_instance_server.this.ip_ids) == 2
    error_message = "Both IPs are in ip_ids: a missing one would be detached by an apply."
  }

  assert {
    condition     = scaleway_instance_server.this.replace_on_type_change == false
    error_message = "A type change resizes the machine, never replaces it."
  }

  assert {
    condition     = tolist(scaleway_instance_server.this.tags) == tolist(["dev", "mairie360"])
    error_message = "Tags are sorted like the API returns them (no perpetual diff)."
  }

  assert {
    condition     = output.public_ipv4 == "192.0.2.10" && output.server_id == "44444444-4444-4444-4444-444444444444"
    error_message = "Outputs: the IPv4 for the inventory, the server id without zone."
  }
}

run "root_volume_is_block_storage" {
  command = apply

  assert {
    condition     = scaleway_instance_server.this.root_volume[0].volume_type == "sbs_volume" && scaleway_instance_server.this.root_volume[0].size_in_gb == 30
    error_message = "The root disk is a Block Storage volume of the requested size, like the existing machines."
  }
}

run "refuses_unknown_iops" {
  command = plan

  variables {
    root_volume_iops = 7000
  }

  expect_failures = [var.root_volume_iops]
}
