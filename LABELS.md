# GCPリソースラベル設定

## 概要
このドキュメントでは、Difyプロジェクトに付与するラベルの設定方法とコスト分析の手順について説明します。

## ラベル戦略

### 標準ラベル
すべてのリソースに以下のラベルが自動的に付与されます：

```hcl
labels = {
  managed_by  = "terraform"      # リソース管理ツール
  project     = "dify"           # プロジェクト識別子（DifyとLINE Botを区別）
  component   = "ai-platform"    # コンポーネント名
  environment = "dev"            # 環境（自動付与）
}
```

### ラベルのカスタマイズ
`terraform.tfvars`でラベルをカスタマイズできます：

```hcl
labels = {
  managed_by  = "terraform"
  project     = "dify"           # ← DifyとLINE Botを区別するための重要なラベル
  component   = "ai-platform"
}
```

## 付与されるリソース

以下のGCPリソースにラベルが付与されます：

### 1. Cloud Run
- `dify-service` (メインサービス)
- `dify-sandbox` (サンドボックス環境)

### 2. Artifact Registry
- `dify-nginx-repo` (Nginxイメージリポジトリ)
- `dify-api-repo` (APIイメージリポジトリ)
- `dify-web-repo` (Webイメージリポジトリ)
- `dify-plugin-daemon-repo` (プラグインデーモンリポジトリ)
- `dify-sandbox-repo` (サンドボックスリポジトリ)

### 3. Storage
- `google_storage_bucket.dify_storage` (ストレージバケット)

### 4. Cloud SQL
- `postgres-instance` (PostgreSQLインスタンス)

### 5. Redis
- `dify-redis` (Redisインスタンス)

### 6. Filestore
- `dify-filestore` (Filestoreインスタンス)

## コスト分析方法

### 1. Cloud Consoleでのコスト確認

#### プロジェクト別（Dify vs LINE Bot）
1. Cloud Console > Billing > Reports
2. フィルター > ラベル > `project`
3. 値を選択：
   - `dify` - Dify関連コスト
   - `linebot` - LINE Bot関連コスト

#### 環境別
1. フィルター > ラベル > `environment`
2. 値を選択：`dev`, `staging`, `prod`

#### コンポーネント別
1. フィルター > ラベル > `component`
2. 値を選択：`ai-platform`

### 2. BigQueryでのコスト分析

詳細なコスト分析には、Billing Export to BigQueryを使用します：

```sql
-- プロジェクト別月次コスト
SELECT
  labels.value AS project_name,
  FORMAT_DATE('%Y-%m', DATE(usage_start_time)) AS month,
  SUM(cost) AS total_cost
FROM
  `project-id.dataset.gcp_billing_export_v1_XXXXXX`
WHERE
  labels.key = 'project'
GROUP BY
  project_name, month
ORDER BY
  month DESC, total_cost DESC;

-- サービス別コスト（Dify関連のみ）
SELECT
  service.description AS service_name,
  SUM(cost) AS total_cost
FROM
  `project-id.dataset.gcp_billing_export_v1_XXXXXX`
WHERE
  labels.key = 'project' AND labels.value = 'dify'
  AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
GROUP BY
  service_name
ORDER BY
  total_cost DESC;

-- 環境別・サービス別コスト
SELECT
  env.value AS environment,
  service.description AS service_name,
  SUM(cost) AS total_cost
FROM
  `project-id.dataset.gcp_billing_export_v1_XXXXXX`,
  UNNEST(labels) AS env
WHERE
  env.key = 'environment'
  AND DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
GROUP BY
  environment, service_name
ORDER BY
  environment, total_cost DESC;
```

### 3. gcloudコマンドでのラベル確認

```bash
# Cloud Runサービスのラベル確認
gcloud run services describe dify-service \
  --region=asia-northeast1 \
  --format='value(metadata.labels)'

# Artifact Registryのラベル確認
gcloud artifacts repositories describe dify-nginx-repo \
  --location=asia-northeast1 \
  --format='value(labels)'

# Cloud SQLのラベル確認
gcloud sql instances describe postgres-instance \
  --format='value(settings.userLabels)'

# Redisのラベル確認
gcloud redis instances describe dify-redis \
  --region=asia-northeast1 \
  --format='value(labels)'

# Filestoreのラベル確認
gcloud filestore instances describe dify-filestore \
  --location=asia-northeast1-b \
  --format='value(labels)'

# Storage Bucketのラベル確認
gsutil label get gs://your-project-id_dify
```

## ベストプラクティス

### 1. 一貫性のあるラベル使用
- すべてのリソースに同じラベルキーを使用
- 値は小文字とハイフンのみ使用（`kebab-case`）

### 2. プロジェクト識別ラベル
- **重要**: `project` ラベルを必ず設定
- LINE BotとDifyのコストを明確に区別するため

### 3. 環境ラベル
- `environment` ラベルは自動的に付与されます
- dev/staging/prodで一貫した値を使用

## デプロイ時のラベル付与

デプロイスクリプト `deploy-dify.sh` を使用すると、Terraform state bucketにも自動的にラベルが付与されます：

```bash
# デプロイ実行
./deploy-dify.sh your-project-id asia-northeast1

# ラベルの確認
gsutil label get gs://your-project-id-terraform-state-dify/
```

Terraform state bucketには以下のラベルが付与されます：
- `managed_by: terraform`
- `project: dify`
- `component: ai-platform`
- `environment: dev` (または staging/prod)
- `purpose: terraform-state`

## トラブルシューティング

### ラベルが反映されない
```bash
# Terraformで再適用
cd dify/terraform/environments/dev
terraform apply -var-file=terraform.tfvars
```

### 既存リソースへのラベル追加
既存のリソースにラベルを追加する場合も、Terraformが自動的に更新します（ダウンタイムなし）。

## 参考リンク
- [GCP Labels Best Practices](https://cloud.google.com/resource-manager/docs/creating-managing-labels)
- [Cost Management with Labels](https://cloud.google.com/billing/docs/how-to/bq-examples)
