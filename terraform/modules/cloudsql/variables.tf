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

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}