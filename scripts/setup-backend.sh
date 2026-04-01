#!/bin/bash
# =============================================================
# setup-backend.sh
# Run this ONCE before your first 'terraform init'.
# Creates the S3 bucket and DynamoDB table for Terraform state.
#
# WHY RUN MANUALLY AND NOT IN TERRAFORM:
# Chicken-and-egg problem: Terraform needs the backend to exist
# BEFORE it can store state. You can't use Terraform to create
# the thing Terraform needs to run. Must be done with AWS CLI.
# =============================================================
# Define the log file name
LOG_FILE="setup_$(date +%Y%m%d_%H%M%S).log"

# Redirect all output (stdout) and errors (stderr) to both the console and the log file
exec > >(tee -i "$LOG_FILE") 2>&1

echo "--- Script started at $(date) ---"
echo "Logging to: $LOG_FILE"

set -euo pipefail

REGION="ap-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="devops-portfolio-tf-state-${ACCOUNT_ID}"
TABLE="devops-portfolio-tf-locks"

echo "Using account: ${ACCOUNT_ID}"
echo "Creating S3 bucket: ${BUCKET}"
echo "Creating DynamoDB table: ${TABLE}"
echo ""

# Create S3 bucket
# if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
#   echo "✅ S3 bucket already exists: ${BUCKET}"
# else
#   aws s3api create-bucket \
#     --bucket "${BUCKET}" \
#     --region "${REGION}" \
#     --create-bucket-configuration LocationConstraint="${REGION}"
#   echo "✅ S3 bucket created: ${BUCKET}"
# fi

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "✅ S3 bucket already exists and you own it: ${BUCKET}"
else
  echo "Bucket not found or not accessible. Attempting to create..."
  # Try to create it, but handle the case where it might already exist 
  # (avoids crashing if head-bucket missed it)
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}" || \
    echo "⚠️ Bucket creation skipped (it might already exist or be owned by you)."
fi

# Enable versioning (allows rolling back state if corrupted)
aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled
echo "✅ Versioning enabled"

# Enable encryption (state file contains sensitive data)
aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'
echo "✅ Encryption enabled"

# Block public access (state file must NEVER be public)
aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "✅ Public access blocked"

# Create DynamoDB table for state locking
if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" &>/dev/null 2>&1; then
  echo "✅ DynamoDB table already exists: ${TABLE}"
else
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
  aws dynamodb wait table-exists --table-name "${TABLE}" --region "${REGION}"
  echo "✅ DynamoDB table created: ${TABLE}"
fi

echo ""
echo "✅ Backend setup complete!"
echo ""
echo "Now update infra/terraform/versions.tf:"
echo "  Replace: devops-portfolio-tf-state-YOURACCOUNTID"
echo "  With:    ${BUCKET}"
echo ""
echo "Then run:"
echo "  cd infra/terraform"
echo "  terraform init"