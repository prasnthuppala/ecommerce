# =============================================================
# versions.tf
# WHY THIS FILE:
# This file pins every provider and Terraform itself to exact
# version ranges. Without pinning, 'terraform init' pulls the
# LATEST provider which can break your infrastructure silently
# when a provider releases breaking changes.
#
# RULE: ~> 5.0 means "accept 5.x, never 6.x"
#       This is the safest version constraint in production.
# =============================================================

terraform {
  required_version = ">= 1.5.0"
  # Minimum Terraform CLI version. Ensures team uses compatible CLI.

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
      # AWS provider ~> 5.0 = accept 5.anything but NOT 6.x
      # Version 5.x has all features we need: EKS, VPC, ECR, IAM OIDC
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
      # TLS provider: used to read the EKS OIDC certificate thumbprint
      # for the GitHub Actions OIDC trust policy
    }
  }

  # =============================================================
  # REMOTE STATE — WHY S3 + DYNAMODB:
  #
  # Default state = local file (terraform.tfstate on your laptop)
  # Problems with local:
  #   - Laptop dies → state lost → Terraform thinks NOTHING exists
  #     → next apply creates DUPLICATE resources (you pay double)
  #   - Two people can't collaborate (state conflicts)
  #   - No history, no rollback
  #
  # S3 backend:
  #   - State file lives in S3 (durable, versioned, encrypted)
  #   - DynamoDB = state LOCK (prevents two applies running simultaneously)
  #     Without lock: person A and person B apply at same time →
  #     state corruption → infrastructure in unknown state
  #
  # FIRST TIME SETUP (run once before terraform init):
  # See: ../scripts/setup-tf-backend.sh
  #
  # The bucket and table names must match what you created.
  # Replace YOURACCOUNTID with your actual AWS account ID (12 digits)
  # Find it: aws sts get-caller-identity --query Account --output text
  # =============================================================
  backend "s3" {
    bucket = "devops-portfolio-tf-state-672120082663"
    key    = "eks/terraform.tfstate"
    region = "ap-south-1"
    # dynamodb_table = "devops-portfolio-tf-locks"
    #  profile        = "default"
    #  shared_config_files = ["~/.aws/config"]
    use_lockfile = true
    encrypt      = true
    # encrypt = true: state file is AES-256 encrypted at rest in S3
    # CRITICAL: your tfstate contains kubeconfig tokens, IAM role ARNs,
    # and other sensitive data. Never store it unencrypted.
  }
}
