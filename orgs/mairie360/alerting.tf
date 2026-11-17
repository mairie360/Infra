# Alert channel of the group (MAIR-623): e-mail, through the Cockpit alert
# manager of the group's project. Every alert rule of the group's data sources
# (alerts/, pushed by the Apply workflow: MAIR-621, MAIR-622) ends up here.
# One alert manager per project and region; it existed before this repository
# (enabled from the console with the team address) and is adopted by import.

resource "scaleway_cockpit_alert_manager" "this" {
  project_id = var.project_id
  region     = "fr-par"

  dynamic "contact_points" {
    for_each = var.alert_emails
    content {
      email = contact_points.value
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

import {
  for_each = var.import_alert_manager ? toset(["this"]) : toset([])
  to       = scaleway_cockpit_alert_manager.this
  id       = "fr-par/${var.project_id}/1"
}
