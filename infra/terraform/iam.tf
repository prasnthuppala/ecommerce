# =============================================================
# iam.tf
# =============================================================
# IAM (Identity and Access Management) controls WHO can do WHAT
# on AWS. There are 3 types of IAM entities here:
#
# 1. EKS Cluster Role   — what the EKS control plane can do
# 2. Node Group Role    — what EC2 nodes can do
# 3. GitHub OIDC Role   — what GitHub Actions can do (no static keys)
#
# PRODUCTION RULE: Never use AdministratorAccess for any role.
# Every role gets ONLY the specific policies it needs.
# This is the Principle of Least Privilege.
# =============================================================

# ══ 1. EKS CLUSTER IAM ROLE ═══════════════════════════════════
# The EKS control plane needs AWS permissions to:
# - Create and manage network interfaces (for pods)
# - Write logs to CloudWatch
# - Authenticate worker nodes
resource "aws_iam_role" "eks_cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Trust policy: "Only the EKS service can assume this role"
      # This prevents any person or other service from using it.
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  # This AWS-managed policy gives EKS the exact permissions it needs.
  # Contains ~20 specific actions. Not AdministratorAccess.
}

# ══ 2. NODE GROUP IAM ROLE ════════════════════════════════════
# Worker nodes (EC2 instances) need permissions to:
# - Register themselves with the EKS cluster
# - Pull Docker images from ECR
# - Write logs and metrics to CloudWatch
# - Configure VPC networking (CNI plugin)
resource "aws_iam_role" "eks_nodes" {
  name = "${local.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Only EC2 instances can assume this role.
      # Not you, not GitHub Actions — only the nodes themselves.
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  # Allows nodes to: register with cluster, describe cluster, etc.
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  # VPC CNI plugin needs to: assign ENIs (network interfaces) to pods,
  # attach/detach IPs. Without this: pods get no network interface = no traffic.
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  # Allows nodes to PULL images from ECR. Read-only.
  # Nodes pull the image when a pod is scheduled on them.
  # They don't need to push — only CI does that.
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.eks_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # Systems Manager allows AWS engineers to shell into nodes WITHOUT SSH.
  # No SSH key management, no open port 22.
  # Production best practice: disable SSH completely, use SSM instead.
}

# ══ 3. GITHUB ACTIONS OIDC ROLE ═══════════════════════════════
# WHY OIDC INSTEAD OF AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY:
#
# Traditional approach: create an IAM user → generate access keys
# → store in GitHub Secrets as AWS_ACCESS_KEY_ID etc.
# Problems:
#   - Keys never expire (long-lived = higher compromise risk)
#   - Must rotate manually
#   - If GitHub is breached, keys are exposed
#   - Every repo might have different keys → key sprawl
#
# OIDC approach:
# 1. GitHub generates a short-lived JWT (15 min) for each workflow run
# 2. JWT is signed by GitHub's OIDC provider (token.actions.githubusercontent.com)
# 3. AWS reads the JWT, verifies GitHub's signature using GitHub's public key
# 4. AWS checks the claims: is it from YOUR repo? YOUR branch?
# 5. AWS issues 15-minute STS credentials
# Result: zero static secrets. Credentials auto-expire. Can't be leaked.

# First: tell AWS to trust GitHub's OIDC provider
data "tls_certificate" "github_actions" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
  # Fetches GitHub's OIDC thumbprint. AWS uses this to verify JWT signatures.
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions.certificates[0].sha1_fingerprint]
  # This resource says: "AWS, trust JWTs issued by GitHub's OIDC provider"
  # It's a one-time setup. After this, any GitHub workflow can request
  # AWS credentials (if the trust policy allows their specific repo).

  tags = local.common_tags
}

# The IAM role GitHub Actions will assume
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          # SECURITY GATE: Only JWTs from YOUR specific repo can assume this role.
          # repo:username/repo-name:* means any branch/PR/tag in your repo.
          # Even if GitHub itself is compromised, only YOUR repo's tokens work.
          # Change :* to :ref:refs/heads/main to restrict to main branch only.
        }
      }
    }]
  })

  tags = local.common_tags
}

# What GitHub Actions can do with this role
resource "aws_iam_role_policy" "github_actions" {
  name = "${var.project_name}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
        # GetAuthorizationToken is account-level, can't be scoped to a repo.
        # All it does is generate a docker login token. Not sensitive.
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:CreateRepository",
          "ecr:ListImages",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/${var.project_name}/*"
        # Scoped to only YOUR project's ECR repos.
        # Can't push to any other account or project's registry.
      },
      {
        Sid    = "EKSAccess"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters",
        ]
        Resource = "*"
        # DescribeCluster: needed by 'aws eks update-kubeconfig' to
        # download the cluster's API endpoint and CA certificate.
        # Without this: kubectl can't connect to the cluster.
      }
    ]
  })
}
