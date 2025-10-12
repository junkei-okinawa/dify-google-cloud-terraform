variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "google_storage_bucket_name" {
  type = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}