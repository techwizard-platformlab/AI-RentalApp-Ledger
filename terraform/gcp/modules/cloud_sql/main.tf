# =============================================================================
# GCP Cloud SQL — PostgreSQL 16
# Tier: db-f1-micro (dev) / db-g1-small (qa) — cheapest GCP SQL tiers.
# Private IP via VPC peering for secure GKE → DB communication.
# Secrets stored in GCP Secret Manager.
# =============================================================================

resource "google_project_service" "sqladmin" {
  project            = var.project_id
  service            = "sqladmin.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# Secret Manager API — must be enabled before creating secrets in this module.
# The secret_manager module also enables this but runs in parallel; explicit
# enablement here guarantees the API is up before cloud_sql secrets are created.
resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Random password for DB admin
resource "random_password" "db_admin" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# Random Django SECRET_KEY
resource "random_password" "django_secret_key" {
  length  = 64
  special = true
}

# ── VPC Peering for private IP (GKE → Cloud SQL) ──────────────────────────────
# google_compute_global_address and google_service_networking_connection both
# require the full network self_link URL, not the short resource ID.
resource "google_compute_global_address" "private_ip_range" {
  name          = "${var.environment}-sql-private-ip"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_network_self_link
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = var.vpc_network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]

  depends_on = [google_project_service.servicenetworking]
}

# ── Cloud SQL Instance ─────────────────────────────────────────────────────────
resource "google_sql_database_instance" "this" {
  name             = "${var.environment}-${var.region_short}-psql"
  project          = var.project_id
  region           = var.region
  database_version = "POSTGRES_16"

  deletion_protection = false   # allow destroy in dev/qa

  settings {
    tier              = var.db_tier
    availability_type = var.environment == "prod" ? "REGIONAL" : "ZONAL"

    disk_size       = 10    # GiB — minimum
    disk_type       = "PD_SSD"
    disk_autoresize = true

    backup_configuration {
      enabled                        = true
      start_time                     = "03:00"
      point_in_time_recovery_enabled = false   # only for prod
      backup_retention_settings {
        retained_backups = 7
      }
    }

    ip_configuration {
      ipv4_enabled    = false   # private IP only
      private_network = var.vpc_network_id
    }

    database_flags {
      name  = "max_connections"
      value = "100"
    }

    insights_config {
      query_insights_enabled = false   # saves cost in dev/qa
    }

    user_labels = var.labels
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

# ── Database ───────────────────────────────────────────────────────────────────
resource "google_sql_database" "rental" {
  name     = "rental_db"
  instance = google_sql_database_instance.this.name
  project  = var.project_id
}

# ── Database user ──────────────────────────────────────────────────────────────
resource "google_sql_user" "app_user" {
  name     = "rentaladmin"
  instance = google_sql_database_instance.this.name
  password = random_password.db_admin.result
  project  = var.project_id
}

# ── Secret Manager — store all DB + app credentials ───────────────────────────
resource "google_secret_manager_secret" "db_host" {
  secret_id = "${var.environment}-db-host"
  project   = var.project_id
  replication {
    auto {}
  }
  labels     = var.labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_host" {
  secret      = google_secret_manager_secret.db_host.id
  secret_data = google_sql_database_instance.this.private_ip_address
}

resource "google_secret_manager_secret" "db_name" {
  secret_id = "${var.environment}-db-name"
  project   = var.project_id
  replication {
    auto {}
  }
  labels     = var.labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_name" {
  secret      = google_secret_manager_secret.db_name.id
  secret_data = google_sql_database.rental.name
}

resource "google_secret_manager_secret" "db_user" {
  secret_id = "${var.environment}-db-user"
  project   = var.project_id
  replication {
    auto {}
  }
  labels     = var.labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_user" {
  secret      = google_secret_manager_secret.db_user.id
  secret_data = google_sql_user.app_user.name
}

resource "google_secret_manager_secret" "db_password" {
  secret_id = "${var.environment}-db-password"
  project   = var.project_id
  replication {
    auto {}
  }
  labels     = var.labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_admin.result
}

resource "google_secret_manager_secret" "django_secret_key" {
  secret_id = "${var.environment}-django-secret-key"
  project   = var.project_id
  replication {
    auto {}
  }
  labels     = var.labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "django_secret_key" {
  secret      = google_secret_manager_secret.django_secret_key.id
  secret_data = random_password.django_secret_key.result
}

# ── Grant GKE node SA access to secrets ───────────────────────────────────────
locals {
  db_secrets = {
    db_host          = google_secret_manager_secret.db_host
    db_name          = google_secret_manager_secret.db_name
    db_user          = google_secret_manager_secret.db_user
    db_password      = google_secret_manager_secret.db_password
    django_secret_key = google_secret_manager_secret.django_secret_key
  }
}

resource "google_secret_manager_secret_iam_member" "gke_accessor" {
  for_each = local.db_secrets

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_service_account}"
}
