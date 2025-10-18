project_id                              = "your-project-id" # replace with your project id
region                                  = "your-region"     # replace with your region
environment                             = "dev"
dify_version                            = "latest"
dify_plugin_daemon_version              = "latest-local"
dify_sandbox_version                    = "latest"
nginx_repository_id                     = "dify-nginx-repo"
web_repository_id                       = "dify-web-repo"
api_repository_id                       = "dify-api-repo"
plugin_daemon_repository_id             = "dify-plugin-daemon-repo"
sandbox_repository_id                   = "dify-sandbox-repo"
secret_key                              = "your-secret-key" # replace with a generated value (run command `openssl rand -base64 42`)
db_username                             = "postgres"
db_password                             = "difyai123456"
db_port                                 = "5432"
db_database                             = "dify"
db_database_plugin                      = "dify_plugin"
db_deletion_protection                  = true
storage_type                            = "google-storage"
google_storage_bucket_name              = "dify"
vector_store                            = "pgvector"
indexing_max_segmentation_tokens_length = "1000"
cloud_run_ingress                       = "INGRESS_TRAFFIC_ALL"            # recommend to setup load balancer and use "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
plugin_daemon_key                       = "your-plugin-daemon-key"         # replace with a generated value (run command `openssl rand -base64 42`)
plugin_dify_inner_api_key               = "your-plugin-dify-inner-api-key" # replace with a generated value (run command `openssl rand -base64 42`)

# ========================================
# Dev環境用コスト削減設定
# ========================================

# Filestore設定
# Dev環境: 1024GB = 約$195/月（GCP仕様上の最小値、1TiB未満はインスタンス料金が加算される）
# 本番環境: 1024GB以上に変更推奨
filestore_capacity_gb = 1024

# Redis設定（コスト削減のため）
# Dev環境: BASIC tier, 1GB = 約$30/月（STANDARD_HAの約50%削減）
# 本番環境: STANDARD_HA tier, 5GB 推奨 = 約$150/月
redis_tier = "BASIC"
redis_memory_size_gb = 1

# Cloud SQL設定（コスト削減のため）
# Dev環境: db-custom-1-3840 (1 vCPU, 3.75GB), 20GB HDD = 約$30/月（70%削減）
# 本番環境: db-custom-2-8192 (2 vCPU, 8GB), 100GB SSD 推奨 = 約$100/月
db_tier = "db-custom-1-3840"
db_disk_size = 20
db_disk_type = "PD_HDD"
db_availability_type = "ZONAL"
db_backup_enabled = false

labels = {
  managed_by  = "terraform"
  project     = "dify"
  component   = "ai-platform"
}
