output "cluster_name" { value = google_container_cluster.this.name }
output "cluster_endpoint" { value = google_container_cluster.this.endpoint }
output "cluster_id" { value = google_container_cluster.this.id }
output "node_service_account_email" { value = google_service_account.gke_nodes.email }
output "workload_identity_pool" { value = "${var.project_id}.svc.id.goog" }

output "kubeconfig_command" {
  description = "Run this command to configure kubectl after apply"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --zone ${var.cluster_location} --project ${var.project_id}"
}
