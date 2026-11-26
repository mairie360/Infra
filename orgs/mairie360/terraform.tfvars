project_id = "716a44bd-7d6f-4940-87ca-711e62799cd0"

instances = {
  dev     = { machine = { tier = "small" } }
  staging = { machine = { tier = "small" } }
  prod    = { machine = { tier = "small" } }
}

# Public names: mairie360-eip.fr moves from o2switch to Scaleway
# Domains. Before the apply: add the domain as an external domain in Scaleway
# Domains, check extra_records against the o2switch zone export (nothing of it
# may be missing, the mail of the team depends on it), apply from a
# workstation, then move the name servers at the registrar.
dns_zone = "mairie360-eip.fr"

# Names that follow a machine of the group (no address written here).
machine_records = {
  "*"          = "prod"
  "dev"        = "dev"
  "*.dev"      = "dev"
  "staging"    = "staging"
  "*.staging"  = "staging"
  "prod"       = "prod"
  "*.prod"     = "prod"
  "argocd-hub" = "argocd"
}

# DMARC: p=quarantine with aggregate reports to dmarc@mairie360.fr (the Resend
# inbox, read through its API) from
# 2026-11-26; p=reject on 2026-12-28 if the reports only show Resend and
# o2switch (mairie360/Deploiment docs/en/external-attack-campaigns.md). The
# monthly reconnaissance checks both domains.
extra_records = {
  # mairie360-eip.fr, copied from the o2switch zone.
  apex          = { name = "", type = "A", data = "51.158.96.108" }
  www           = { name = "www", type = "CNAME", data = "mairie360-eip.fr." }
  ftp           = { name = "ftp", type = "CNAME", data = "mairie360-eip.fr." }
  argocd        = { name = "argocd", type = "A", data = "51.158.96.108" }
  argocd_backup = { name = "argocd.backup", type = "A", data = "51.158.96.108" }
  mail          = { name = "mail", type = "A", data = "109.234.167.90" }
  webmail       = { name = "webmail", type = "A", data = "109.234.167.90" }
  cpanel        = { name = "cpanel", type = "A", data = "109.234.167.90" }
  autodiscover  = { name = "autodiscover", type = "A", data = "109.234.167.90" }
  autoconfig    = { name = "autoconfig", type = "A", data = "109.234.167.90" }
  mx            = { name = "", type = "MX", data = "mail.mairie360-eip.fr.", priority = 0 }
  spf           = { name = "", type = "TXT", data = "v=spf1 ip4:109.234.167.90 +a +mx +include:spf.jabatus.fr ~all" }
  dkim_o2switch = { name = "default._domainkey", type = "TXT", data = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAu69m7rJTPmvuFMy8FHw5UcN1Gux6CRnWMtumEoyckIssWJ+IILSGeJk2whv2VfxNrGQJfSfO2Xv2yUWApFxBscABUjHec9MUYVZuBIX9Yf9oV5VJ31IXx67pfZSNnnnEvYTjEiB0ZP4VvhtsJXZiwFCB97Rqm+vrnn6zCXj//3KczMbs4UV3p0cNMSy6JAgnOhdf+bYZ6IOJ3ObTuG4wdfRy54XCh8OduXYXIz5pimOaoPiMmqgQoOhtuCvwa9Wz5kJZy8dwBlceFxBSL/4wGMGAEh8r9WPn3oaaQqQt0oAHdQBE96ZzOFkTUOJUl67fl1YkxzHilYX8fJlghwItwQIDAQAB;" }
  dkim_resend   = { name = "resend._domainkey", type = "TXT", data = "p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC9hA7qzUuIxbzpwva7xG0usM4F3URwql0NjfBvV04T6j120uUSHYLRldhMM6UYTW8TeRXFGO7EtyCbzBhyzjvkZLwUUMYb0pc5mgoOXWTiuvfJLwEyBpukiX1KKazs02VO4YACcvyVyPyIa+r7ReYBPmj+1qmxPoWBj56pfOyAGQIDAQAB" }
  resend_spf    = { name = "send", type = "TXT", data = "v=spf1 include:amazonses.com ~all" }
  resend_mx     = { name = "send", type = "MX", data = "feedback-smtp.eu-west-1.amazonses.com.", priority = 10 }
  dmarc         = { name = "_dmarc", type = "TXT", data = "v=DMARC1; p=quarantine; rua=mailto:dmarc@mairie360.fr; adkim=r; aspf=r" }

  # mairie360.fr (already in Scaleway Domains): it sends through Resend
  # (send.mairie360.fr) and receives the spoofed e-mail test (MX to Resend,
  # receiving enabled on the domain). Delete its former "_dmarc p=none" record
  # in the console before the apply.
  fr_spf = { zone = "mairie360.fr", name = "", type = "TXT", data = "v=spf1 -all" }
  # mairie360.fr accepts the DMARC reports of mairie360-eip.fr (RFC 7489 7.1).
  fr_dmarc_reports = { zone = "mairie360.fr", name = "mairie360-eip.fr._report._dmarc", type = "TXT", data = "v=DMARC1" }
  fr_dmarc         = { zone = "mairie360.fr", name = "_dmarc", type = "TXT", data = "v=DMARC1; p=quarantine; rua=mailto:dmarc@mairie360.fr; adkim=r; aspf=r" }
}

# MX of the Resend receiving inbox on mairie360.fr: the value Resend shows once
# receiving is enabled on the domain (Domains > mairie360.fr > Receiving).
# resend_receiving_mx = "<value shown by Resend>"

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
