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

# ファイルの場所を取得
SCRIPT_DIR=$(cd $(dirname $0); pwd)
cd $SCRIPT_DIR/terraform/environments/dev

# 1. Cloud SQL インスタンスの削除
# Cloud SQLインスタンスが残っている場合のみデータベースを削除
if gcloud sql instances describe postgres-instance --project=$PROJECT_ID &>/dev/null; then
    # 事前にdeletion_protectionを無効化してからデータベースを削除
    echo "1. Cloud SQLインスタンスとデータベースを削除します..."
    gcloud sql instances patch postgres-instance --no-deletion-protection --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - deletion_protection の更新に失敗、またはインスタンスが存在しません"
    # データベース削除
    gcloud sql databases delete dify --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify データベースは既に削除済みまたは存在しません"
    gcloud sql databases delete dify_plugin --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify_plugin データベースは既に削除済みまたは存在しません"
    # インスタンス削除
    gcloud sql instances delete postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - postgres-instance は既に削除済みまたは存在しません"
    echo "  - Cloud SQLインスタンスとデータベースを削除しました"
else
    echo "  - Cloud SQLインスタンスが存在しないため、データベース削除をスキップします"
fi

# 2. Cloud Storage の削除
echo "2. Cloud Storage の削除..."
BUCKET_NAME_CLOUD_BUILD="${PROJECT_ID}_cloudbuild"
BUCKET_NAME_DIFY="${PROJECT_ID}_dify"
BUCKET_NAME="${PROJECT_ID}-terraform-state-dify"
if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME_CLOUD_BUILD" &>/dev/null; then
    gsutil -m rm -r "gs://$BUCKET_NAME_CLOUD_BUILD"
    echo "  - バケット gs://$BUCKET_NAME_CLOUD_BUILD を削除しました"

else
    echo "  - バケット gs://$BUCKET_NAME_CLOUD_BUILD は存在しません"
fi

# 3. Terraform destroy を実行
# Terraformが依存関係を解決し、リソースを正しい順序で削除します。
# dev環境ではCloud Runの削除保護は無効になっているため、追加の操作は不要です。
echo "3. 'terraform destroy' を実行します..."
echo "   VPC関連リソースの解放遅延により、一度失敗することがあります。"

# 1回目のdestroy実行
if terraform destroy -auto-approve; then
    # Terraform destroy成功後にdifyバケットとstateバケットを削除
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME_DIFY" &>/dev/null; then
        gsutil -m rm -r "gs://$BUCKET_NAME_DIFY"
        echo "  - バケット gs://$BUCKET_NAME_DIFY を削除しました"
    else
        echo "  - バケット gs://$BUCKET_NAME_DIFY は既に削除されています"
    fi
    echo "   Terraform stateバケットを削除します..."
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" &>/dev/null; then
        gsutil -m rm -r "gs://$BUCKET_NAME"
        echo "  - Terraform stateバケット gs://$BUCKET_NAME を削除しました"
    else
        echo "  - Terraform stateバケット gs://$BUCKET_NAME は既に削除されています"
    fi
    echo "🎉 1回目の試行でリソースの削除が完了しました。"
    exit 0
fi

# Cloud Run が未削除の場合は削除
if gcloud run services describe dify-service --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "   Cloud Run サービス dify-service を削除します..."
    gcloud run services delete dify-service --region=$REGION --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify-service は既に削除済みまたは存在しません"
fi
if gcloud run services describe dify-sandbox --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "   Cloud Run サービス dify-sandbox を削除します..."
    gcloud run services delete dify-sandbox --region=$REGION --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify-sandbox は既に削除済みまたは存在しません"
fi

# 5. ファイアウォールルールの削除
echo "5. ファイアウォールルールの削除..."
FIREWALL_RULES=$(gcloud compute firewall-rules list --filter="network:dify-vpc" --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
for rule in $FIREWALL_RULES; do
    echo "  - ファイアウォールルール $rule を削除..."
    gcloud compute firewall-rules delete $rule --project=$PROJECT_ID --quiet 2>/dev/null || echo "    ※ $rule の削除に失敗しました"
done

# 失敗した場合、GCPバックエンドでのリソース解放を待機
wait_seconds=180
echo "1回目の試行でエラーが発生しました。VPC関連リソースが解放されるのを待機します..."
echo "${wait_seconds}分間待機してから再試行します..."
sleep $wait_seconds

if gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
    echo "  - VPC dify-vpc が残っているため、関連リソースを個別に削除します"

    # 1. デフォルトルートを削除（ローカルルートはスキップ）
    echo "    - デフォルトルートを削除します..."
    ROUTES=$(gcloud compute routes list --filter="network:dify-vpc AND NOT name~default-route" --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
    for route in $ROUTES; do
        echo "      - デフォルトルート $route を削除..."
        gcloud compute routes delete $route --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $route は削除できないルートのためスキップします"
    done

    # 2. VPC Peering の削除
    echo "    - VPC peering を削除します..."
    # 指定順序でVPC peeringを削除
    PEERING_ORDER=("firestore-peer" "redis-peer" "servicenetworking-googleapis-com")
    for peering_prefix in "${PEERING_ORDER[@]}"; do
        # 該当するpeeringを検出
        PEERINGS=$(gcloud compute networks peerings list --network=dify-vpc --project=$PROJECT_ID --format="value(peerings.name)" 2>/dev/null | grep "$peering_prefix" || true)
        for peering in $(echo "$PEERINGS" | tr ';' '\n'); do
            if [ -n "$peering" ] && [ "$peering" != "dify-vpc" ]; then
                echo "      - VPC peering $peering を削除..."
                gcloud compute networks peerings delete $peering --network=dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $peering の削除に失敗しました"
            fi
        done
    done
    # 残りのpeeringを削除
    REMAINING_PEERINGS=$(gcloud compute networks peerings list --network=dify-vpc --project=$PROJECT_ID --format="value(peerings.name)" 2>/dev/null || true)
    for peering in $(echo "$REMAINING_PEERINGS" | tr ';' '\n'); do
        if [ -n "$peering" ] && [ "$peering" != "dify-vpc" ]; then
            echo "      - 残りのVPC peering $peering を削除..."
            gcloud compute networks peerings delete $peering --network=dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $peering の削除に失敗しました"
        fi
    done

    # 3. NAT Router の削除
    echo "    - NAT Router を削除します..."
    if gcloud compute routers nats describe nat-config --router=nat-router --region=$REGION --project=$PROJECT_ID &>/dev/null; then
        echo "      - NAT config が存在するため、先に削除します..."
        # NAT configを先に削除
        gcloud compute routers nats delete nat-config --router=nat-router --region=$REGION --project=$PROJECT_ID --quiet 2>/dev/null || echo "      ※ nat-config の削除に失敗しました"
        # Routerを削除
        gcloud compute routers delete nat-router --region=$REGION --project=$PROJECT_ID --quiet 2>/dev/null || echo "      ※ nat-router の削除に失敗しました"
    fi

    # 4. 静的IPアドレスの削除
    echo "    - 静的IPアドレスを削除します..."
    # private-ip-range (グローバル) - 動的検出
    PRIVATE_IP=$(gcloud compute addresses list --filter="name:private-ip-range" --global --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
    if [ -n "$PRIVATE_IP" ]; then
        echo "      - Private IP range $PRIVATE_IP を削除..."
        gcloud compute addresses delete $PRIVATE_IP --global --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $PRIVATE_IP の削除に失敗しました"
    fi

    # 5. サブネットを削除
    echo "    - サブネットを削除します..."
    SUBNETS=$(gcloud compute networks subnets list --network=dify-vpc --project=$PROJECT_ID --format="value(name,region)" 2>/dev/null || true)
    while read -r subnet region; do
        echo "      - サブネット $subnet ($region) を削除..."
        gcloud compute networks subnets delete $subnet --region=$region --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $subnet の削除に失敗しました"
    done <<< "$SUBNETS"

    # 6. VPC を削除（最後に削除）
    echo "    - VPC dify-vpc を削除..."
    gcloud compute networks delete dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "      ※ VPC の削除に失敗しました"
else
    echo "  - VPC dify-vpc は存在しません"
fi

# 既に削除されたリソースを状態から削除
echo "    - 既に削除されたリソースを状態からクリア..."
terraform state list 2>/dev/null | while read -r resource; do
    echo "      - リソース $resource の存在確認..."
    # リソースの種類に応じて存在確認
    if echo "$resource" | grep -q "google_sql_database\|google_sql_user"; then
        # Cloud SQL関連はインスタンス存在確認（個別削除されているはず）
        if ! gcloud sql instances describe postgres-instance --project=$PROJECT_ID &>/dev/null; then
            echo "        ※ Cloud SQLインスタンスが存在しないため、$resource を状態から削除"
            terraform state rm "$resource" 2>/dev/null || echo "          ※ $resource の状態削除に失敗しました"
        fi
    elif echo "$resource" | grep -q "google_sql_database_instance"; then
        # Cloud SQLインスタンス自体も確認
        if ! gcloud sql instances describe postgres-instance --project=$PROJECT_ID &>/dev/null; then
            echo "        ※ Cloud SQLインスタンスが個別削除されているため、$resource を状態から削除"
            terraform state rm "$resource" 2>/dev/null || echo "          ※ $resource の状態削除に失敗しました"
        fi
    elif echo "$resource" | grep -q "google_cloud_run_v2_service"; then
        # Cloud Runサービス存在確認
        service_name=$(echo "$resource" | sed 's/.*services\/\([^\/]*\).*/\1/')
        if ! gcloud run services describe "$service_name" --region=asia-northeast1 --project=$PROJECT_ID &>/dev/null; then
            echo "        ※ Cloud Runサービス $service_name が存在しないため、$resource を状態から削除"
            terraform state rm "$resource" 2>/dev/null || echo "          ※ $resource の状態削除に失敗しました"
        fi
    elif echo "$resource" | grep -q "google_storage_bucket"; then
        # Cloud Storage存在確認
        bucket_name=$(echo "$resource" | sed 's/.*buckets\/\([^\/]*\).*/\1/')
        if ! gsutil ls -b "gs://$bucket_name" &>/dev/null; then
            echo "        ※ Cloud Storageバケット $bucket_name が存在しないため、$resource を状態から削除"
            terraform state rm "$resource" 2>/dev/null || echo "          ※ $resource の状態削除に失敗しました"
        fi
    elif echo "$resource" | grep -q "google_compute_network"; then
        # VPC存在確認
        if ! gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
            echo "        ※ VPC dify-vpc が存在しないため、$resource を状態から削除"
            terraform state rm "$resource" 2>/dev/null || echo "          ※ $resource の状態削除に失敗しました"
        fi
    fi
done

# 2回目のdestroy実行
echo "   'terraform destroy' を再試行します..."
if terraform destroy -auto-approve; then
    echo "🎉 2回目の試行でリソースの削除が完了しました。"
    
    # Terraform destroy成功後にdifyバケットとstateバケットを削除
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME_DIFY" &>/dev/null; then
        gsutil -m rm -r "gs://$BUCKET_NAME_DIFY"
        echo "  - バケット gs://$BUCKET_NAME_DIFY を削除しました"
    else
        echo "  - バケット gs://$BUCKET_NAME_DIFY は既に削除されています"
    fi
    echo "   Terraform stateバケットを削除します..."
    if gsutil ls -p "$PROJECT_ID" "gs://$BUCKET_NAME" &>/dev/null; then
        gsutil -m rm -r "gs://$BUCKET_NAME"
        echo "  - Terraform stateバケット gs://$BUCKET_NAME を削除しました"
    else
        echo "  - Terraform stateバケット gs://$BUCKET_NAME は既に削除されています"
    fi
else
    echo "回目の試行でもエラーが発生しました。"
    echo "   GCPコンソールで残存リソースを確認し、手動で削除してください。"
    exit 1
fi


# ファイルの場所に戻る
cd $SCRIPT_DIR
echo ""
echo "=== 削除完了 ==="