output "ar_repository_id" {
  description = "Shared AR repository ID — set as TF_VAR_ar_repository_id in env workflows"
  value       = google_artifact_registry_repository.shared.repository_id
}

output "ar_location" {
  description = "Shared AR location — set as TF_VAR_ar_location in env workflows"
  value       = google_artifact_registry_repository.shared.location
}

output "ar_repository_url" {
  description = "Full Docker push/pull URL: {location}-docker.pkg.dev/{project}/{repo}"
  value       = "${google_artifact_registry_repository.shared.location}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.shared.repository_id}"
}
