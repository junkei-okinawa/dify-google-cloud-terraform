variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "dify_version" {
  type = string
}

variable "dify_sandbox_version" {
  type = string
}

variable "cloud_run_ingress" {
  type = string
}

variable "nginx_repository_id" {
  type = string
}

variable "web_repository_id" {
  type = string
}

variable "api_repository_id" {
  type = string
}

variable "plugin_daemon_repository_id" {
  type = string
}

variable "sandbox_repository_id" {
  type = string
}

variable "secret_key" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}

variable "db_port" {
  type = string
}

variable "db_database" {
  type = string
}

variable "db_database_plugin" {
  type = string
}

variable "db_deletion_protection" {
  type = bool
}

variable "storage_type" {
  type = string
}

variable "google_storage_bucket_name" {
  type = string
}

variable "vector_store" {
  type = string
}

variable "indexing_max_segmentation_tokens_length" {
  type = number
}

variable "plugin_daemon_key" {
  type = string
}

variable "plugin_dify_inner_api_key" {
  type = string
}

variable "dify_plugin_daemon_version" {
  type = string
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB (GCP仕様上の最小値: 1024GB)"
  type        = number
  default     = 1024  # GCP BASIC_HDDの最小値（1TiB未満はインスタンス料金$44.22が加算）
}

# Redis コスト削減設定
variable "redis_tier" {
  description = "Redis tier (BASIC for dev, STANDARD_HA for prod)"
  type        = string
  default     = "BASIC"  # Dev環境ではBASIC（STANDARD_HAの約半分のコスト）
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1  # Dev環境では最小の1GB
}

# Cloud SQL コスト削減設定
variable "db_tier" {
  description = "Database instance tier"
  type        = string
  default     = "db-custom-1-3840"  # Dev: 1 vCPU, 3.75GB RAM（約60%コスト削減）
}

variable "db_disk_size" {
  description = "Database disk size in GB"
  type        = number
  default     = 20  # Dev: 20GB（100GBから80%削減）
}

variable "db_disk_type" {
  description = "Database disk type (PD_SSD or PD_HDD)"
  type        = string
  default     = "PD_HDD"  # Dev: HDDでコスト削減（SSDの約1/3）
}

variable "db_availability_type" {
  description = "Availability type (ZONAL or REGIONAL)"
  type        = string
  default     = "ZONAL"  # Dev: ZONALでコスト削減
}

variable "db_backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = false  # Dev: バックアップ無効でコスト削減
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    managed_by  = "terraform"
    project     = "dify"
    component   = "ai-platform"
  }
}
