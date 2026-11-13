#!/usr/bin/env bash
# Apply campus-app to the k3s cluster. Secrets come from AWS Secrets Manager — never from git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
PREFIX="${RESOURCE_PREFIX:-ci-anton-belov-0564}"
IMAGE_TAG="${IMAGE_TAG:?set IMAGE_TAG to immutable git SHA}"

need() { command -v "$1" >/dev/null || { echo "missing $1"; exit 1; }; }
need aws
need kubectl
need jq

ECR_URL=$(cd "$ROOT/terraform" && terraform output -raw ecr_repository_url)
MYSQL_IP=$(cd "$ROOT/terraform" && terraform output -raw mysql_primary_private_ip)
CH_IP=$(cd "$ROOT/terraform" && terraform output -raw clickhouse_private_ip)
BUCKET=$(cd "$ROOT/terraform" && terraform output -raw bucket_name)

APP_RW_PW=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$PREFIX/db-app-rw" --query SecretString --output text)
SECRET_KEY=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$PREFIX/app-secret-key" --query SecretString --output text)
CH_PW=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$PREFIX/clickhouse" --query SecretString --output text)

# Kubeconfig from SSM (written by k3s-server bootstrap)
aws ssm get-parameter --region "$REGION" --name "/$PREFIX/kubeconfig" --with-decryption --query 'Parameter.Value' --output text > /tmp/kubeconfig-$PREFIX
export KUBECONFIG=/tmp/kubeconfig-$PREFIX

IMAGE="$ECR_URL:$IMAGE_TAG"
# Keep ${DB_PASSWORD} placeholder — app URL-encodes from DB_PASSWORD secret
DB_URL="mysql+pymysql://app_rw:\${DB_PASSWORD}@${MYSQL_IP}:3306/campus"
CLICKHOUSE_URL="clickhouse://analytics:${CH_PW}@${CH_IP}:8123/campus"

kubectl apply -f "$ROOT/deploy/k8s/namespace.yaml"

# ECR pull secret
PASS=$(aws ecr get-login-password --region "$REGION")
kubectl -n campus-app create secret docker-registry ecr-pull \
  --docker-server="$(echo "$ECR_URL" | cut -d/ -f1)" \
  --docker-username=AWS \
  --docker-password="$PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n campus-app create secret generic campus-app-secrets \
  --from-literal=SECRET_KEY="$SECRET_KEY" \
  --from-literal=DB_PASSWORD="$APP_RW_PW" \
  --from-literal=DB_URL="$DB_URL" \
  --from-literal=CLICKHOUSE_URL="$CLICKHOUSE_URL" \
  --dry-run=client -o yaml | kubectl apply -f -

# Patch non-secret config
kubectl -n campus-app apply -f "$ROOT/deploy/k8s/configmap.yaml"
kubectl -n campus-app patch configmap campus-app-config --type merge -p "{\"data\":{\"BUCKET\":\"$BUCKET\"}}"

# Render deployment with image
sed "s|REPLACE_ECR_IMAGE|$IMAGE|g" "$ROOT/deploy/k8s/deployment.yaml" | kubectl apply -f -
kubectl apply -f "$ROOT/deploy/k8s/service.yaml"
kubectl apply -f "$ROOT/deploy/k8s/ingress.yaml"
kubectl apply -f "$ROOT/deploy/k8s/hpa.yaml"

kubectl -n campus-app set env deployment/campus-app GIT_SHA="$IMAGE_TAG" APP_VERSION="$IMAGE_TAG"
kubectl -n campus-app rollout status deployment/campus-app --timeout=300s
kubectl -n campus-app get pods -o wide
kubectl -n campus-app get hpa

rm -f /tmp/kubeconfig-$PREFIX
echo "Deployed $IMAGE"
