# Still the platform's project: refused by validation on purpose. Replace it with
# the mairie360-attack project (scripts/tf.sh iam output attack_project_id) once
# iam/ is applied, before the first apply of this root.
project_id = "716a44bd-7d6f-4940-87ca-711e62799cd0"

# true only for the window of an external attack campaign
# (mairie360/Deploiment docs/en/external-attack-campaigns.md); back to false,
# then apply, to destroy the server once it ends. The IP stays reserved.
enabled = false
