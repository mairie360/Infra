# The bucket holding the Terraform states, this one included. Created once by
# scripts/bootstrap.sh with a local state, which it then moves into the bucket.

resource "scaleway_object_bucket" "state" {
  name       = var.state_bucket
  project_id = var.project_id
  region     = "fr-par"
  tags = {
    managed-by = "terraform"
    purpose    = "terraform-state"
  }

  # Every state write is kept: a broken apply is rolled back by restoring
  # the previous version of the state object.
  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_acl" "state" {
  bucket     = scaleway_object_bucket.state.id
  project_id = var.project_id
  acl        = "private"

  # Removing it would leave the bucket on its provider default ACL.
  lifecycle {
    prevent_destroy = true
  }
}
