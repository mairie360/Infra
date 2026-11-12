terraform {
  # State in the versioned bucket of bootstrap/. Credentials: AWS_ACCESS_KEY_ID
  # and AWS_SECRET_ACCESS_KEY, set from the scw CLI profile by scripts/tf.sh.
  # No state lock: run one apply at a time (CI only plans).
  backend "s3" {
    bucket = "mairie360-tfstate"
    key    = "iam.tfstate"
    region = "fr-par"

    endpoints = {
      s3 = "https://s3.fr-par.scw.cloud"
    }

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
