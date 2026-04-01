# =============================================================
# variables.tf
# WHY A VARIABLES FILE:
# Hard-coding values in resources means you can't reuse the same
# Terraform code for dev vs prod. Variables let you pass different
# values for each environment without changing the resource code.
#
# RULE: Never hardcode AWS account IDs, region names, or sensitive
# values inside resource blocks. They always belong in variables.
# =============================================================

variable "project_name" {
  type        = string
  default     = "devops-portfolio"
  description = "Project name — used as prefix for all AWS resource names. Keeps resources organized and identifiable in the AWS console."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment name. Used in resource names and tags. For portfolio: dev. Same Terraform code works for prod by changing this."
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod"
    # WHY VALIDATION: Catches typos before resources are created.
    # 'terraform validate' will fail immediately instead of creating
    # resources with a wrong name like 'devv-cluster'.
  }
}

variable "aws_region" {
  type        = string
  default     = "ap-south-1"
  description = "AWS region. ap-south-1 = Mumbai. Closest to India. Use us-east-1 if outside India — it's the cheapest region globally."
}

variable "kubernetes_version" {
  type        = string
  default     = "1.31"
  description = "EKS Kubernetes version. EKS supports a version for 14 months then forces upgrade. Pin to latest stable."
}

# =============================================================
# VPC NETWORKING
# =============================================================

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "CIDR block for the VPC. /16 = 65,536 IPs. More than enough. RULE: Never use 192.168.x.x for cloud VPCs — conflicts with home routers."
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDRs for private subnets (EKS nodes live here). /24 = 256 IPs per subnet. One per AZ. Nodes are private = not reachable from internet."
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
  description = "CIDRs for public subnets (Load Balancers live here). /24 = 256 IPs. One per AZ. Public = has a route to the Internet Gateway."
}

# =============================================================
# EKS NODE GROUP — LOW COST FOR PORTFOLIO
# WHY t3.medium NOT t3.micro:
# t3.micro = 1 vCPU, 1GB RAM. EKS system pods alone need ~600MB.
# With 5 microservices + system pods on a t3.micro: OOMKill guaranteed.
# t3.medium = 2 vCPU, 4GB. Comfortable: system pods + your 5 services.
#
# WHY SPOT:
# Spot = spare AWS capacity at 60-80% discount.
# t3.medium On-Demand: ~$0.0416/hr
# t3.medium Spot:      ~$0.0125/hr ← 70% cheaper
# For a 3-hour portfolio demo: ($0.10 control + $0.0125 node) × 3 = ~$0.34
#
# PRODUCTION DIFFERENCE:
# Production: 3+ nodes, multi-AZ, mix of On-Demand + Spot,
#             PodDisruptionBudget, multiple instance types for Spot.
# Our setup: 1 node (cheaper), single AZ, Spot only.
# Process is identical. Resources are sized down.
# =============================================================

variable "node_instance_types" {
  type        = list(string)
  default     = ["t3.medium", "t3a.medium"]
  description = "EC2 instance types for EKS nodes. Multiple types = if AWS runs out of t3.medium Spot, it tries t3a.medium. Reduces Spot interruption risk."
}

variable "node_desired_size" {
  type        = number
  default     = 1
  description = "Desired node count. 1 for dev/demo. Production would use 2-3 across multiple AZs for HA."
}

variable "node_min_size" {
  type        = number
  default     = 1
  description = "Minimum nodes. Cluster Autoscaler won't go below this."
}

variable "node_max_size" {
  type        = number
  default     = 3
  description = "Maximum nodes. Cluster Autoscaler won't exceed this. Protects against runaway scaling costs."
}

variable "node_disk_size" {
  type        = number
  default     = 20
  description = "EBS volume size in GB for each node. 20GB holds OS + our 5 Alpine images (~130MB each = 650MB total). 20GB is plenty."
}

# =============================================================
# GITHUB OIDC — for GitHub Actions to authenticate to AWS
# =============================================================

variable "github_org" {
  type        = string
  description = "Your GitHub username or organization name. Used in OIDC trust policy to restrict which repos can assume the IAM role."
}

variable "github_repo" {
  type        = string
  description = "Your GitHub repository name (without org prefix). Example: 'devops-portfolio'"
}

# =============================================================
# YOUR IAM USER — to access the cluster via kubectl
# =============================================================

variable "your_iam_user_arn" {
  type        = string
  description = "Your IAM user ARN. This gives YOUR user access to kubectl after the cluster is created. Find it: aws sts get-caller-identity --query Arn"
}

# =============================================================
# TAGS
# WHY TAGGING EVERYTHING:
# Tags are KEY for cost management. Without tags, your AWS bill shows
# "EC2: $45" with no way to know which project/env caused it.
# With tags: Cost Explorer filters by tag → per-project cost breakdown.
# RULE: Every resource must have Project, Environment, ManagedBy tags.
# =============================================================

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags to apply to all resources. These merge with the default tags defined in providers.tf."
}
