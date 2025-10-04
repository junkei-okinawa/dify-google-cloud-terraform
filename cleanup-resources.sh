#!/bin/bash

# Dify GCP リソース削除スクリプト (Terraform主体)
# 使用方法: ./cleanup-resources.sh <project-id> <region>

set -e

PROJECT_ID=$1
REGION=$2

if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ]; then
    echo "使用方法: $0 <project-id> <region>"
    echo "例: $0 my-gcp-project asia-northeast1"
    exit 1
fi

echo "=== Dify GCP リソース削除スクリプト ==="
echo "プロジェクト: $PROJECT_ID"
echo "リージョン: $REGION"
echo ""

# 1. Cloud SQL インスタンスの削除保護を無効化
# Terraformが削除できるように、deletion_protectionフラグを無効化します。
echo "1. Cloud SQL インスタンスの削除保護を無効化しています..."
gcloud sql instances patch postgres-instance --no-deletion-protection --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - Cloud SQLインスタンスが見つからないか、すでに保護は無効です。"

# 2. Terraform destroy を実行
# Terraformが依存関係を解決し、リソースを正しい順序で削除します。
# dev環境ではCloud Runの削除保護は無効になっているため、追加の操作は不要です。
echo "2. 'terraform destroy' を実行します..."
echo "   VPC関連リソースの解放遅延により、一度失敗することがあります。"
cd terraform/environments/dev

# 1回目のdestroy実行
if terraform destroy -auto-approve; then
    echo "🎉 1回目の試行でリソースの削除が完了しました。"
    exit 0
fi

# 失敗した場合、GCPバックエンドでのリソース解放を待機
echo "回目の試行でエラーが発生しました。VPC関連リソースが解放されるのを待機します..."
echo "分間待機してから再試行します..."
sleep 180

# 2回目のdestroy実行
echo "   'terraform destroy' を再試行します..."
if terraform destroy -auto-approve; then
    echo "🎉 2回目の試行でリソースの削除が完了しました。"
else
    echo "回目の試行でもエラーが発生しました。"
    echo "   GCPコンソールで残存リソースを確認し、手動で削除してください。"
    exit 1
fi

echo ""
echo "=== 削除完了 ==="