project_id = "716a44bd-7d6f-4940-87ca-711e62799cd0"

instances = {
  dev     = { machine = { tier = "small" } }
  staging = { machine = { tier = "small" } }
  prod    = { machine = { tier = "small" } }
}

# Public names: mairie360-eip.fr is still served by o2switch. Set it once the
# zone is in Scaleway Domains (records first imported or recreated there).
# dns_zone = "mairie360-eip.fr"

# Existing console name kept: a rename is harmless but not the point of the import.
argocd_machine = { name = "argocd hub", type = "DEV1-M", root_volume_size_gb = 20 }

# The n8n machine, console name kept.
n8n_machine = { name = "mairie360 n8n", type = "DEV1-S", root_volume_size_gb = 20 }

# MAIR-637: machines made in the console, adopted on the first apply.
imported_machines = {
  argocd  = { server_id = "99b5d1eb-d99f-4419-a5a4-4f30ca62672f", ipv4_id = "340961fd-aeee-4a0a-9d6e-e1c517803a75", ipv6_id = "65928d58-2b09-44a5-9708-cd16b832c604" }
  dev     = { server_id = "c325d057-6eb3-490d-9b6e-1f87b5ed6b16", ipv4_id = "ca804b30-bc5d-4373-ac79-21008b7b891a", ipv6_id = "297d8394-263a-4474-a289-7d44d3c3bc3b" }
  staging = { server_id = "4d5bd565-a36d-4167-9439-aa845f6205ae", ipv4_id = "9540ab87-0d79-438c-9b97-98f5dbd64eb8", ipv6_id = "656bbe9a-eb43-48db-a32a-0137195510c1" }
  prod    = { server_id = "db2e6eae-3b69-4ef2-89fe-cdd090a8aa49", ipv4_id = "ffbebd24-b805-4a77-ae4b-2746fd355511", ipv6_id = "df461dfb-e807-4d2d-a383-b43de7e07f5b" }
  n8n     = { server_id = "970b0169-cdc6-4b72-a615-d6f5cec24812", ipv4_id = "b120ac7f-061b-4add-a8fa-75e8e7d376fd", ipv6_id = "da9fff0c-e7ef-4637-bb00-9dad9c076b09" }
}

# MAIR-623: alerts go by e-mail to the team mailbox (Cockpit alert manager,
# enabled in the console before this repository, adopted).
alert_emails         = ["mairie360@gmail.com"]
import_alert_manager = true
