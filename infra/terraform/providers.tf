# =============================================================
# providers.tf
# =============================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
      Repository  = "github.com/${var.github_org}/${var.github_repo}"
    }
    # WHY DEFAULT TAGS ON THE PROVIDER:
    # Every single AWS resource created by this Terraform configuration
    # automatically gets these tags — even if the resource block doesn't
    # explicitly set tags. This guarantees 100% tagging coverage.
    # Without this: engineers forget to tag resources. Cost Explorer
    # shows unattributed costs. Finance team is unhappy.
    # With this: every EC2 node, every security group, every EBS volume
    # is tagged. Filter by Project=devops-portfolio in Cost Explorer
    # to see exactly what this cluster costs.
  }
}
