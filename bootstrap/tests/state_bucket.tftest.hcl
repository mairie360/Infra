# The state bucket is private and versioned. Provider mocked.
mock_provider "scaleway" {}

variables {
  project_id = "00000000-0000-0000-0000-000000000000"
}

run "private_versioned_bucket" {
  command = apply

  assert {
    condition     = scaleway_object_bucket.state.name == "mairie360-tfstate"
    error_message = "The backend blocks use mairie360-tfstate."
  }

  assert {
    condition     = scaleway_object_bucket.state.versioning[0].enabled
    error_message = "The state bucket must be versioned."
  }

  assert {
    condition     = scaleway_object_bucket_acl.state.acl == "private"
    error_message = "The state bucket must be private."
  }
}
