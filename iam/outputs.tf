output "ci_application_ids" {
  description = "IAM application id of each CI workflow: scw iam api-key create application-id=<id>."
  value       = { for name, app in scaleway_iam_application.ci : name => app.id }
}

output "bucket_keys" {
  description = "Per \"<env>/<purpose>\": bucket, IAM application and vault secret of its key (scripts/issue-bucket-keys.sh)."
  value = {
    for k, b in local.instance_buckets : k => merge(b, { application_id = scaleway_iam_application.bucket[k].id })
  }
}

output "attack_project_id" {
  description = "Project of the attack source: project_id of attack-source/terraform.tfvars."
  value       = scaleway_account_project.attack.id
}

output "campaign_application_ids" {
  description = "IAM application id of the attack campaign workflows (spoofed e-mail test, DNS reconnaissance): scw iam api-key create application-id=<id>."
  value       = { for name, app in scaleway_iam_application.campaign : name => app.id }
}
