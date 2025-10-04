variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "project_id" {
  description = "The GCP project ID."
  type        = string
}

variable "region" {
  description = "The GCP region."
  type        = string
}

variable "dify_version" {
  description = "The Dify version."
  type        = string
}

variable "dify_sandbox_version" {
  description = "The Dify sandbox version."
  type        = string
}

variable "cloud_run_ingress" {
  description = "The ingress setting for Cloud Run."
  type        = string
}

variable "nginx_repository_id" {
  description = "The Artifact Registry repository ID for nginx."
  type        = string
}

variable "web_repository_id" {
  description = "The Artifact Registry repository ID for web."
  type        = string
}

variable "api_repository_id" {
  description = "The Artifact Registry repository ID for api."
  type        = string
}

variable "sandbox_repository_id" {
  description = "The Artifact Registry repository ID for sandbox."
  type        = string
}

variable "vpc_network_name" {
  description = "The name of the VPC network."
  type        = string
}

variable "vpc_subnet_name" {
  description = "The name of the VPC subnet."
  type        = string
}

variable "plugin_daemon_repository_id" {
  description = "The Artifact Registry repository ID for plugin-daemon."
  type        = string
}

variable "plugin_daemon_key" {
  description = "The secret key for the plugin daemon."
  type        = string
}

variable "plugin_dify_inner_api_key" {
  description = "The inner API key for Dify plugin."
  type        = string
}

variable "dify_plugin_daemon_version" {
  description = "The Dify plugin daemon version."
  type        = string
}

variable "db_database" {
  description = "The name of the database."
  type        = string
}

variable "db_database_plugin" {
  description = "The name of the plugin database."
  type        = string
}

variable "filestore_ip_address" {
  description = "The IP address of the Filestore instance."
  type        = string
}

variable "filestore_fileshare_name" {
  description = "The fileshare name of the Filestore instance."
  type        = string
}

variable "shared_env_vars" {
  description = "Shared environment variables for containers."
  type        = map(string)
}

variable "min_instance_count" {
  description = "The minimum number of instances for Cloud Run."
  type        = number
}

variable "max_instance_count" {
  description = "The maximum number of instances for Cloud Run."
  type        = number
}

variable "storage_bucket_name" {
  description = "The name of the storage bucket."
  type        = string
}