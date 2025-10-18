variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_network_name" {
  type = string
}

variable "redis_tier" {
  description = "Redis tier (BASIC for dev, STANDARD_HA for prod)"
  type        = string
  default     = "BASIC"  # Dev環境用：約75%コスト削減
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1  # Dev環境では最小の1GB
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}