# =============================================================
# terraform.tfvars
# =============================================================
# This file contains the ACTUAL VALUES for your variables.
# WHY SEPARATE FROM variables.tf:
#   variables.tf = declares WHAT inputs exist (types, defaults, descriptions)
#   terraform.tfvars   = sets the ACTUAL values for this deployment
#
# IMPORTANT: Add this to .gitignore IF it contains secrets.
# This file has no secrets — just config. Safe to commit.
# Secrets go into AWS Secrets Manager or GitHub Secrets, NOT here.
# =============================================================

project_name       = "ecommerce"
environment        = "dev"
aws_region         = "ap-south-1"
kubernetes_version = "1.31"

# ---------- Networking ----------
vpc_cidr             = "10.0.0.0/16"
private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnet_cidrs  = ["10.0.101.0/24", "10.0.102.0/24"]

# ---------- Node Group (low cost for portfolio) ----------
node_instance_types = ["t3.medium", "t3a.medium"]
node_desired_size   = 1
node_min_size       = 1
node_max_size       = 3
node_disk_size      = 20

# ---------- GitHub OIDC (replace with your values) ----------
github_org  = "prasnthuppala"
github_repo = "ecommerce"

# ---------- Your IAM User (replace with yours) ----------
# Find yours: aws sts get-caller-identity --query Arn --output text
your_iam_user_arn = "arn:aws:iam::672120082663:root"
