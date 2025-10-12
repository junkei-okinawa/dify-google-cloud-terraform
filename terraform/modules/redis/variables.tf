variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc_network_name" {
  type = string
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}