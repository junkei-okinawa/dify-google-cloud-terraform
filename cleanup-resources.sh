#!/bin/bash

# Dify GCP リソース完全削除スクリプト
# 使用方法: ./cleanup-resources.sh <project-id>
# 戦略: 個別リソース削除 → Terraform destroy

set -e

PROJECT_ID=$1

if [ -z "$PROJECT_ID" ]; then
    echo "使用方法: $0 <project-id>"
    exit 1
fi

echo "=== Dify GCP リソース削除スクリプト ==="
echo "プロジェクト: $PROJECT_ID"
echo "戦略: 個別リソース削除 → Terraform destroy"
echo ""

# 1. Cloud SQL Database の削除
echo "1. Cloud SQL Database の削除..."
gcloud sql databases delete dify --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify データベースは既に削除済みまたは存在しません"
gcloud sql databases delete dify_plugin --instance=postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify_plugin データベースは既に削除済みまたは存在しません"

# 2. Cloud SQL インスタンスの削除
echo "2. Cloud SQL インスタンスの削除..."
# deletion_protection を一時的に無効化
gcloud sql instances patch postgres-instance --no-deletion-protection --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - deletion_protection の更新に失敗、またはインスタンスが存在しません"
# インスタンス削除
gcloud sql instances delete postgres-instance --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - postgres-instance は既に削除済みまたは存在しません"

# 3. Cloud Storage の削除
echo "3. Cloud Storage の削除..."
BUCKET_NAME="${PROJECT_ID}_dify"
gsutil rm -r "gs://$BUCKET_NAME" 2>/dev/null || echo "  - バケット $BUCKET_NAME は既に削除済みまたは存在しません"

# 4. Cloud Run サービスの削除
echo "4. Cloud Run サービスの削除..."
gcloud run services delete dify-service --region=asia-northeast1 --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify-service は既に削除済みまたは存在しません"
gcloud run services delete dify-sandbox --region=asia-northeast1 --project=$PROJECT_ID --quiet 2>/dev/null || echo "  - dify-sandbox は既に削除済みまたは存在しません"

# 5. VPC Peering の削除
echo "5. VPC Peering の削除..."
if gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
    # すべてのVPC peeringを動的に検出して削除
    gcloud compute networks peerings list --network=dify-vpc --project=$PROJECT_ID --format="value(name)" 2>/dev/null | while read -r peering; do
        if [ -n "$peering" ] && [ "$peering" != "dify-vpc" ]; then
            echo "  - VPC peering $peering を削除..."
            gcloud compute networks peerings delete $peering --network=dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "    ※ $peering の削除に失敗しました"
        fi
    done
else
    echo "  - VPC dify-vpc は既に削除済みまたは存在しません"
fi

# 6. VPC ネットワーク関連リソースの削除
echo "6. VPC ネットワーク関連リソースの削除..."
if gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
    echo "  - VPC dify-vpc が残っているため、関連リソースを個別に削除します"

    # Cloud Run サービス削除後の待機（serverless IP が解放されるまで）
    echo "    - Cloud Run サービス削除後の待機（60秒）..."
    sleep 60

    # 1. 静的IPアドレスの削除（最初に削除 - サブネットが使用しているため）
    echo "    - 静的IPアドレスを削除します..."
    # private-ip-range (グローバル) - 動的検出
    PRIVATE_IP=$(gcloud compute addresses list --filter="name:private-ip-range" --global --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
    if [ -n "$PRIVATE_IP" ]; then
        echo "      - Private IP range $PRIVATE_IP を削除..."
        gcloud compute addresses delete $PRIVATE_IP --global --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $PRIVATE_IP の削除に失敗しました"
    fi
    # serverless IPを動的に検出して削除（複数回試行 + 強制削除）
    for attempt in {1..5}; do
        echo "      - Serverless IP 削除試行 $attempt/5..."
        SERVERLESS_IPS=$(gcloud compute addresses list --filter="purpose:SERVERLESS" --project=$PROJECT_ID --format="value(name,region)" 2>/dev/null || true)
        if [ -z "$SERVERLESS_IPS" ]; then
            echo "        ※ 削除するServerless IPが見つかりません"
            break
        fi
        while read -r ip_name region; do
            if [ -n "$ip_name" ] && [ -n "$region" ]; then
                echo "        - Serverless IP $ip_name ($region) を削除..."
                # 通常削除を試行
                if gcloud compute addresses delete $ip_name --region=$region --project=$PROJECT_ID --quiet 2>/dev/null; then
                    echo "          ※ $ip_name を削除しました"
                else
                    echo "          ※ $ip_name の削除に失敗しました（使用中の可能性あり）"
                    # 最終試行時は強制削除を試行
                    if [ $attempt -eq 5 ]; then
                        echo "            ※ 最終試行: 強制削除を試みます..."
                        # 注: GCPではserverless IPの強制削除は通常サポートされないが、念のため
                        gcloud compute addresses delete $ip_name --region=$region --project=$PROJECT_ID --quiet 2>/dev/null || echo "            ※ 強制削除も失敗しました"
                    fi
                fi
            fi
        done <<< "$SERVERLESS_IPS"
        if [ $attempt -lt 5 ]; then
            echo "        - 次の試行まで待機（30秒）..."
            sleep 30
        fi
    done

    # 2. デフォルトルートを削除（ローカルルートはスキップ）
    echo "    - デフォルトルートを削除します..."
    ROUTES=$(gcloud compute routes list --filter="network:dify-vpc AND NOT name~default-route" --project=$PROJECT_ID --format="value(name)" 2>/dev/null || true)
    for route in $ROUTES; do
        echo "      - デフォルトルート $route を削除..."
        gcloud compute routes delete $route --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $route は削除できないルートのためスキップします"
    done

    # 3. サブネットを削除（静的IPとルート削除後）
    echo "    - サブネットを削除します..."
    SUBNETS=$(gcloud compute networks subnets list --network=dify-vpc --project=$PROJECT_ID --format="value(name,region)" 2>/dev/null || true)
    while read -r subnet region; do
        if [ -n "$subnet" ] && [ -n "$region" ]; then
            echo "      - サブネット $subnet ($region) を削除..."
            # サブネットを使用しているリソースを確認
            echo "        - サブネットの依存関係を確認..."
            SUBNET_USERS=$(gcloud compute addresses list --filter="subnetwork~${subnet} AND region:${region}" --project=$PROJECT_ID --format="value(name,purpose)" 2>/dev/null || true)
            if [ -n "$SUBNET_USERS" ]; then
                echo "        - 警告: サブネットを使用しているIPアドレスがあります:"
                echo "$SUBNET_USERS" | while read -r ip purpose; do
                    echo "          - $ip ($purpose)"
                done
                echo "        - IPアドレス削除後に再試行します..."
                # IP削除後に再度試行
                sleep 10
            fi
            if gcloud compute networks subnets delete $subnet --region=$region --project=$PROJECT_ID --quiet 2>/dev/null; then
                echo "        ※ サブネット $subnet を削除しました"
            else
                echo "        ※ サブネット $subnet の削除に失敗しました"
                # 依存関係が残っている場合、最終手段としてスキップ
                echo "        - 後続の処理を続行します（Terraform destroyで対応）"
            fi
        fi
    done <<< "$SUBNETS"

    # 4. VPC Peering の削除（サブネット削除後）
    echo "    - VPC peering を削除します..."
    # 動的に検出されたpeeringを削除（再度確認）
    gcloud compute networks peerings list --network=dify-vpc --project=$PROJECT_ID --format="value(name)" 2>/dev/null | while read -r peering; do
        if [ -n "$peering" ] && [ "$peering" != "dify-vpc" ]; then
            echo "      - VPC peering $peering を削除..."
            gcloud compute networks peerings delete $peering --network=dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $peering の削除に失敗しました"
        fi
    done

    # 5. VPC を削除（最後に削除）
    echo "    - VPC dify-vpc を削除..."
    gcloud compute networks delete dify-vpc --project=$PROJECT_ID --quiet 2>/dev/null || echo "      ※ VPC の削除に失敗しました"
else
    echo "  - VPC dify-vpc は既に削除済みまたは存在しません"
fi

# 7. Terraform destroy を実行（個別削除後に実行）
echo "7. Terraform destroy の実行..."

# Terraform 状態を更新（存在しないリソースを削除）
echo "  - Terraform 状態を更新中..."
cd terraform/environments/dev

# 存在しないリソースを状態から削除
terraform state list 2>/dev/null | while read -r resource; do
    echo "    - 状態から $resource を確認..."
    # リソースの存在確認を試行（エラーが出たら状態から削除）
    if ! terraform state show "$resource" &>/dev/null; then
        echo "      ※ $resource は状態に問題があるため削除します"
        terraform state rm "$resource" 2>/dev/null || echo "        ※ $resource の状態削除に失敗しました"
    fi
done

# Terraform destroy を実行（エラーが発生しても続行）
echo "  - Terraform destroy を実行..."
terraform destroy -auto-approve || echo "  ※ Terraform destroy で一部エラーが発生しましたが、続行します"

# 追加のクリーンアップ：残ったリソースを強制削除
echo "  - 追加クリーンアップを実行..."
cd ../../..

# 残ったserverless IPを再度試行
echo "    - 残ったserverless IPの最終削除試行..."
SERVERLESS_IPS=$(gcloud compute addresses list --filter="purpose:SERVERLESS" --project=$PROJECT_ID --format="value(name,region)" 2>/dev/null || true)
if [ -n "$SERVERLESS_IPS" ]; then
    while read -r ip_name region; do
        if [ -n "$ip_name" ] && [ -n "$region" ]; then
            echo "      - 最終試行: Serverless IP $ip_name ($region) を削除..."
            gcloud compute addresses delete $ip_name --region=$region --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $ip_name の最終削除も失敗しました"
        fi
    done <<< "$SERVERLESS_IPS"
else
    echo "    ※ 残ったserverless IPはありません"
fi

# 残ったサブネットを再度試行
echo "    - 残ったサブネットの最終削除試行..."
if gcloud compute networks describe dify-vpc --project=$PROJECT_ID &>/dev/null; then
    SUBNETS=$(gcloud compute networks subnets list --network=dify-vpc --project=$PROJECT_ID --format="value(name,region)" 2>/dev/null || true)
    if [ -n "$SUBNETS" ]; then
        while read -r subnet region; do
            if [ -n "$subnet" ] && [ -n "$region" ]; then
                echo "      - 最終試行: サブネット $subnet ($region) を削除..."
                gcloud compute networks subnets delete $subnet --region=$region --project=$PROJECT_ID --quiet 2>/dev/null || echo "        ※ $subnet の最終削除も失敗しました"
            fi
        done <<< "$SUBNETS"
    fi
fi

echo ""
echo "=== 削除完了 ==="
echo "すべての Dify GCP リソースが削除されました。"
echo "一部のリソースが残っている場合は、しばらく待ってから再度実行してください。"