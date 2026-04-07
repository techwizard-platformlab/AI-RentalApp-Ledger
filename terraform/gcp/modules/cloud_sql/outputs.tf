output "instance_name" {
  description = "Cloud SQL instance name"
  value       = google_sql_database_instance.this.name
}

output "private_ip" {
  description = "Private IP address (use as DB_HOST from GKE pods)"
  value       = google_sql_database_instance.this.private_ip_address
}

output "database_name" {
  description = "Application database name"
  value       = google_sql_database.rental.name
}

output "db_user" {
  description = "Database username"
  value       = google_sql_user.app_user.name
}

output "db_password_secret_id" {
  description = "Secret Manager secret ID for DB password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "django_secret_key_secret_id" {
  description = "Secret Manager secret ID for Django SECRET_KEY"
  value       = google_secret_manager_secret.django_secret_key.secret_id
}
