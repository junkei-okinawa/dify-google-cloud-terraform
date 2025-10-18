variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type = string
}

variable "vpc_network_name" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "db_tier" {
  description = "Database instance tier (e.g., db-custom-1-3840 for dev)"
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
  default     = "ZONAL"  # Dev: ZONAL（REGIONALは2倍のコスト）
}

variable "db_backup_enabled" {
  description = "Enable automated backups"
  type        = bool
  default     = false  # Dev: バックアップ無効でコスト削減
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}