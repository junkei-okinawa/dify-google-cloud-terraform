variable "region" {
  type = string
}

variable "vpc_network_name" {
  type = string
}

variable "filestore_capacity_gb" {
  description = "Filestore capacity in GB (minimum 1024 for BASIC_HDD)"
  type        = number
  default     = 1024  # GCP仕様上の最小値（1TiB未満はインスタンス料金が加算）
  
  validation {
    condition     = var.filestore_capacity_gb >= 1024 && var.filestore_capacity_gb <= 63900
    error_message = "Filestore capacity must be between 1024GB and 63900GB (GCP BASIC_HDD tier requirement)."
  }
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}