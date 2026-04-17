output "repository_id" { value = google_artifact_registry_repository.this.repository_id }
output "repository_name" { value = google_artifact_registry_repository.this.name }
output "repository_url" { value = "${var.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.this.repository_id}" }
