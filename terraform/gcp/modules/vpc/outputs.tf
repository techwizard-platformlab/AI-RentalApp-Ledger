output "network_id"          { value = google_compute_network.this.id }
output "network_name"        { value = google_compute_network.this.name }
output "app_subnet_id"       { value = google_compute_subnetwork.app.id }
output "app_subnet_name"     { value = google_compute_subnetwork.app.name }
output "db_subnet_id"        { value = google_compute_subnetwork.db.id }
output "pods_range_name"     { value = "pods" }
output "services_range_name" { value = "services" }
