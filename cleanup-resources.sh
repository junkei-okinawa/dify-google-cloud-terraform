#!/bin/bash

# Dify GCP リソース完全削除スクリプト
# 使用方法: ./cleanup-resources.sh <project-id>

set -e

PROJECT_ID=$1

if [ -z "$PROJECT_ID" ]; then
    echo "使用方法: $0 <project-id>"
    exit 1
fi

echo "=== Dify GCP リソース削除スクリプト ==="
echo "プロジェクト: $PROJECT_ID"
echo ""

# 1. Cloud SQL Database の削除
echo "1. Cloud SQL Database の削除..."
gcloud sql databases delete dify --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify データベースは既に削除済みまたは存在しません"
gcloud sql databases delete dify_plugin --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify_plugin データベースは既に削除済みまたは存在しません"

# 2. Cloud SQL インスタンスの削除（deletion_protection を無効化）
echo "2. Cloud SQL インスタンスの削除..."
# deletion_protection を一時的に無効化
gcloud sql instances patch postgres-instance --no-deletion-protection --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - deletion_protection の更新に失敗、またはインスタンスが存在しません"
# インスタンス削除
gcloud sql instances delete postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - postgres-instance は既に削除済みまたは存在しません"

# 3. Cloud Storage の削除
echo "3. Cloud Storage の削除..."
BUCKET_NAME="${PROJECT_ID}_dify"
gsutil rm -r "gs://$BUCKET_NAME" 2>/dev/null || echo "  - バケット $BUCKET_NAME は既に削除済みまたは存在しません"

# 4. VPC Peering の削除
echo "4. VPC Peering の削除..."
gcloud compute networks peerings delete servicenetworking-googleapis-com --network=dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - VPC Peering は既に削除済みまたは存在しません"

# 5. VPC ネットワークの削除（デフォルトルートがある場合の対応）
echo "5. VPC ネットワークの削除..."
if gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
    # デフォルトルートを検索して削除
    ROUTES=$(gcloud compute routes list --filter="network:dify-vpc AND name~default-route" --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
    for route in $ROUTES; do
        echo "  - デフォルトルート $route を削除..."
        gcloud compute routes delete $route --project=$PROJECT_ID --quiet
    done

    # VPC を削除
    gcloud compute networks delete dify-vpc --project=$PROJECT_ID --quiet
else
    echo "  - VPC dify-vpc は既に削除済みまたは存在しません"
fi

# 6. Terraform destroy の実行
echo "6. Terraform destroy の実行..."
cd terraform/environments/dev
terraform destroy -auto-approve

echo ""
echo "=== 削除完了 ==="
echo "すべての Dify GCP リソースが削除されました。"