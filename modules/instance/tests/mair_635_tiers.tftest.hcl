# MAIR-635: the size of an instance machine comes from its tier; small is what
# dev, staging and prod run today, so moving them to tiers changes nothing.
mock_provider "scaleway" {
  mock_resource "scaleway_secret" {
    defaults = {
      id = "fr-par/11111111-1111-1111-1111-111111111111"
    }
  }
}

variables {
  org_id     = "mairie360"
  env_name   = "prod"
  project_id = "00000000-0000-0000-0000-000000000000"
  machine    = { tier = "small" }
}

run "small_is_the_current_machine" {
  command = plan

  assert {
    condition     = module.machine.type_in_use == "POP2-2C-8G" && module.machine.root_volume_size_gb_in_use == 30
    error_message = "small = POP2-2C-8G with 30 GB, the type of the existing machines (no resize)."
  }
}

run "a_larger_tier_gets_a_larger_machine" {
  command = plan

  variables {
    machine = { tier = "large" }
  }

  assert {
    condition     = module.machine.type_in_use == "POP2-8C-32G" && module.machine.root_volume_size_gb_in_use == 120
    error_message = "large = POP2-8C-32G with 120 GB."
  }
}

run "an_explicit_type_overrides_the_tier" {
  command = plan

  variables {
    machine = { tier = "small", type = "POP2-HM-4C-32G" }
  }

  assert {
    condition     = module.machine.type_in_use == "POP2-HM-4C-32G" && module.machine.root_volume_size_gb_in_use == 30
    error_message = "type overrides the tier's type, the tier still gives the volume."
  }
}

run "an_unknown_tier_is_refused" {
  command = plan

  variables {
    machine = { tier = "xl" }
  }

  expect_failures = [var.machine]
}

run "no_tier_needs_type_and_volume" {
  command = plan

  variables {
    machine = { type = "POP2-2C-8G" }
  }

  expect_failures = [var.machine]
}

run "the_fronts_are_public_k3s_is_not" {
  command = plan

  assert {
    condition     = toset(var.public_ports.tcp) == toset([22, 80, 443])
    error_message = "An instance opens SSH and the fronts (80, 443); 6443 only through WireGuard."
  }
}
