# =============================================================
# outputs.tf
# =============================================================
# WHY OUTPUTS:
# After 'terraform apply', Terraform prints these values.
# They're also accessible via: terraform output <name>
# The CD pipeline uses these to:
#   - Get cluster name for aws eks update-kubeconfig
#   - Get ECR URLs to tag/push images
#   - Get GitHub Actions role ARN for GitHub Secrets
# =============================================================

output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name. Use in: aws eks update-kubeconfig --name <this> --region ap-south-1"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS API server endpoint. kubectl connects here."
}

output "cluster_region" {
  value       = var.aws_region
  description = "AWS region where the cluster was created."
}

output "configure_kubectl" {
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
  description = "Run this command to configure kubectl on your local machine."
}

output "ecr_repository_urls" {
  value = {
    for svc, repo in aws_ecr_repository.services :
    svc => repo.repository_url
  }
  description = "ECR repository URLs for each service. Use in CI to tag and push images."
  # Output format:
  # ecr_repository_urls = {
  #   cart         = "123456789.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio/cart"
  #   product      = "123456789.dkr.ecr.ap-south-1.amazonaws.com/devops-portfolio/product"
  #   payment      = "..."
  #   auth         = "..."
  #   notification = "..."
  # }
}

output "ecr_registry_url" {
  value       = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  description = "Base ECR registry URL for docker login. Use in: aws ecr get-login-password | docker login <this>"
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "GitHub Actions IAM role ARN. Set as AWS_ROLE_ARN in GitHub Secrets → Settings → Secrets → Actions."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks.arn
  description = "EKS OIDC provider ARN. Needed if you create additional IRSA roles for pods."
}

output "node_group_name" {
  value       = aws_eks_node_group.spot.node_group_name
  description = "EKS node group name. Use in AWS console or CLI to check node status."
}

output "cost_reminder" {
  value       = <<-EOT
    ⚠️  COST REMINDER:
    EKS Control Plane: $0.10/hr = $2.40/day
    NAT Gateway:       $0.045/hr = $1.08/day
    t3.medium Spot:    ~$0.0125/hr = $0.30/day
    TOTAL IF LEFT RUNNING: ~$3.78/day

    Run 'terraform destroy' when demo is done!
    Or use the GitHub Actions 'tf-destroy' workflow.
  EOT
  description = "Cost reminder — always destroy when done to avoid charges."
}
