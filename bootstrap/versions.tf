terraform {
  required_version = ">= 1.10"

  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "2.89.0"
    }
  }
}

# Credentials and default project: SCW_* environment variables, else the scw
# CLI profile (~/.config/scw/config.yaml). Resources set project_id explicitly.
provider "scaleway" {
  region = "fr-par"
  zone   = "fr-par-1"
}
