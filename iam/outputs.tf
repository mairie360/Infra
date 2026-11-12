output "ci_application_ids" {
  description = "IAM application id of each CI workflow: scw iam api-key create application-id=<id>."
  value       = { for name, app in scaleway_iam_application.ci : name => app.id }
}
