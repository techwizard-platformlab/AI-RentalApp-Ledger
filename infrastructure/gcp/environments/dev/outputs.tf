output "gke_cluster_name" { value = module.gke.cluster_name }
output "gke_kubeconfig_cmd" { value = module.gke.kubeconfig_command }
output "artifact_registry_url" { value = "${var.ar_location}-docker.pkg.dev/${var.project_id}/${var.ar_repository_id}" }
output "secret_names" { value = module.secret_manager.secret_names }

output "github_secrets_to_set" {
  description = "Set these as GitHub Actions repository secrets"
  value = {
    GCP_WORKLOAD_IDENTITY_PROVIDER = module.workload_identity.workload_identity_provider
    GCP_SERVICE_ACCOUNT            = module.workload_identity.service_account_email
  }
}
