resource "google_service_networking_connection" "private_vpc_connection" {
  provider                = google-beta
  network                 = var.vpc_network_name
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

resource "google_compute_global_address" "private_ip_range" {
  provider      = google-beta
  name          = "private-ip-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = var.vpc_network_name
}


resource "google_sql_database_instance" "postgres_instance" {
  depends_on          = [google_service_networking_connection.private_vpc_connection]
  database_version    = "POSTGRES_15"
  name                = "postgres-instance"
  project             = var.project_id
  region              = var.region
  deletion_protection = var.deletion_protection

  settings {
    activation_policy = "ALWAYS"
    availability_type = var.db_availability_type  # Dev: ZONAL, Prod: REGIONAL
    
    user_labels = var.labels

    backup_configuration {
      backup_retention_settings {
        retained_backups = var.db_backup_enabled ? 7 : 0
        retention_unit   = "COUNT"
      }

      enabled                        = var.db_backup_enabled  # Dev: falseでコスト削減
      location                       = "asia"
      point_in_time_recovery_enabled = var.db_backup_enabled
      start_time                     = "21:00"
      transaction_log_retention_days = var.db_backup_enabled ? 7 : 1
    }

    disk_autoresize       = true
    disk_autoresize_limit = 0
    disk_size             = var.db_disk_size      # Dev: 20GB
    disk_type             = var.db_disk_type       # Dev: PD_HDD

    ip_configuration {
      ipv4_enabled    = true
      private_network = "projects/${var.project_id}/global/networks/${var.vpc_network_name}"
    }

    location_preference {
      zone = "${var.region}-b"
    }

    maintenance_window {
      update_track = "canary"
      day          = 7
    }

    pricing_plan = "PER_USE"
    tier         = var.db_tier  # Dev: db-custom-1-3840 (1 vCPU, 3.75GB)
  }
}

resource "google_sql_database" "dify_database" {
  name     = "dify"
  instance = google_sql_database_instance.postgres_instance.name
  project  = var.project_id

  depends_on = [google_sql_database_instance.postgres_instance]
}

resource "google_sql_database" "dify_plugin_database" {
  name     = "dify_plugin"
  instance = google_sql_database_instance.postgres_instance.name
  project  = var.project_id

  depends_on = [google_sql_database_instance.postgres_instance]
}

resource "google_sql_user" "dify_user" {
  name     = var.db_username
  instance = google_sql_database_instance.postgres_instance.name
  project  = var.project_id
  password = var.db_password

  depends_on = [google_sql_database_instance.postgres_instance]
}
