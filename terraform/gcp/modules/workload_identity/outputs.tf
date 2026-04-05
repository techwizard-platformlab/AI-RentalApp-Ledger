output "workload_identity_provider" {
  description = "Full provider resource name — set as GCP_WORKLOAD_IDENTITY_PROVIDER in GitHub secrets"
  value       = google_iam_workload_identity_pool_provider.github_oidc.name
}

output "service_account_email" {
  description = "Terraform CI service account email — set as GCP_SERVICE_ACCOUNT in GitHub secrets"
  value       = google_service_account.terraform_ci.email
}

output "pool_name" {
  value = google_iam_workload_identity_pool.github.name
}
