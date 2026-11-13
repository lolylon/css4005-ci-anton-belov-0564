#!/usr/bin/env bash
# One-time remote state bootstrap (run before enabling backend.tf).
set -euo pipefail
PREFIX="${RESOURCE_PREFIX:-ci-anton-belov-0564}"
REGION="${AWS_REGION:-us-east-1}"
BUCKET="${PREFIX}-tfstate"
TABLE="${PREFIX}-tf-locks"

aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
  $( [ "$REGION" = "us-east-1" ] && echo "" || echo "--create-bucket-configuration LocationConstraint=$REGION" )

aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws dynamodb create-table \
  --region "$REGION" \
  --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Project,Value="$PREFIX" || true

echo "Copy terraform/backend.tf.example → terraform/backend.tf and run terraform init"
