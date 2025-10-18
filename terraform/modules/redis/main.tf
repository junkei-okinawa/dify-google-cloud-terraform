resource "google_redis_instance" "dify_redis" {
  name               = "dify-redis"
  tier               = var.redis_tier              # Dev: BASIC, Prod: STANDARD_HA
  memory_size_gb     = var.redis_memory_size_gb    # Dev: 1GB（最小）
  region             = var.region
  project            = var.project_id
  redis_version      = "REDIS_6_X"
  reserved_ip_range  = "10.0.1.0/29"

  authorized_network = var.vpc_network_name
  
  labels = var.labels
}
