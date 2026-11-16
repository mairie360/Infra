# E-learning bucket of the instance (MAIR-619): course attachments of
# elearning-api (S3_BUCKET), served through presigned GET URLs. Built from
# scratch: the hand-made `mairie360-eleartning-storage` (typo) was shared by
# every instance and is dropped (its files were accepted as lost). Versioned so
# that an overwrite or a delete can be undone for 30 days.

resource "scaleway_object_bucket" "elearning" {
  name       = module.naming.buckets.elearning
  project_id = var.project_id
  region     = var.region
  tags = {
    managed-by = "terraform"
    purpose    = "elearning-attachments"
    org        = var.org_id
    env        = var.env_name
  }

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id      = "purge-old-versions"
    enabled = true
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload_days = 1
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "scaleway_object_bucket_acl" "elearning" {
  bucket     = scaleway_object_bucket.elearning.id
  project_id = var.project_id
  acl        = "private"

  lifecycle {
    prevent_destroy = true
  }
}
