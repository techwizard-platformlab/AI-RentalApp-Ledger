output "secret_ids" {
  description = "Map of secret name → secret resource ID"
  value       = { for k, v in google_secret_manager_secret.this : k => v.id }
}

output "secret_names" {
  description = "Map of secret name → full secret_id (with env prefix)"
  value       = { for k, v in google_secret_manager_secret.this : k => v.secret_id }
}
