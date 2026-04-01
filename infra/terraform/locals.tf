# =============================================================
# locals.tf
# WHY LOCALS:
# Locals = computed values derived from variables.
# They prevent repeating the same expression in multiple resources.
# RULE: Any value used in 3+ places belongs in locals.
# =============================================================

data "aws_availability_zones" "available" {
  state = "available"
  # Dynamically fetches which AZs exist in your region.
  # ap-south-1 has 3 AZs: ap-south-1a, ap-south-1b, ap-south-1c
  # We take the first 2 (slice below).
  # Using data source = handles AZ deprecations automatically.
}

data "aws_caller_identity" "current" {}
# Fetches: AWS account ID, user ARN, user ID of whoever runs Terraform.
# Used to construct: arn:aws:iam::ACCOUNT_ID:...

locals {
  cluster_name = "${var.project_name}-${var.environment}-cluster"
  # Consistent naming: devops-portfolio-dev-cluster
  # Why include environment: lets you have dev and prod clusters
  # in the same AWS account without name collision.

  azs = slice(data.aws_availability_zones.available.names, 0, 2)
  # Take first 2 AZs. We have 2 private + 2 public subnets (one per AZ).
  # slice(list, start, end) — end is exclusive.

  account_id = data.aws_caller_identity.current.account_id
  # Shorthand. Used in ECR URL construction and IAM ARNs.

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      ClusterName = local.cluster_name
      # ManagedBy = terraform: tells any engineer "don't touch this in console"
      # Resources managed by Terraform must be changed ONLY via Terraform.
      # Manual console changes = state drift → Terraform will revert them.
    },
    var.tags
    # merge() lets callers add extra tags without losing the required ones.
  )

  # ECR base URL for this account/region
  ecr_base_url = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"

  # The 5 service names — single source of truth
  # Used in ECR repo creation and CD pipeline image tags
  services = ["cart", "product", "payment", "auth", "notification"]
}
