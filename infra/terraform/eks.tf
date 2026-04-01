# =============================================================
# eks.tf
# =============================================================
# WHY EKS AND NOT SELF-MANAGED K8S:
# Self-managed K8s = you run etcd, API server, scheduler, controller-manager.
# That's 40+ hours of setup and ongoing patching. Not a portfolio win.
# EKS = AWS manages the control plane. You manage worker nodes.
# You pay $0.10/hr for the control plane. Everything else is EC2.
# This is how real companies run Kubernetes in 2025.
# =============================================================

# ── EKS CLUSTER ────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }


  vpc_config {
    subnet_ids = concat(
      aws_subnet.private[*].id,
      aws_subnet.public[*].id
    )
    # WHY BOTH PUBLIC AND PRIVATE:
    # Control plane ENIs (network interfaces) go in private subnets.
    # The public subnets are for future Load Balancers and NAT.
    # EKS requires at least 2 subnets in different AZs.

    endpoint_private_access = true
    endpoint_public_access  = true
    # private_access = true: nodes inside VPC talk to API server via
    #   private IP. Faster, cheaper (no NAT), more secure.
    # public_access = true: YOU can run kubectl from your laptop.
    #   The API server is reachable from the internet.
    # Production: restrict public_access_cidrs to your office IP.
    # Portfolio dev: open to all (so you can work from anywhere).

    public_access_cidrs = ["0.0.0.0/0"]
    # Production rule: restrict this to your IP: ["YOUR.IP/32"]
    # For portfolio demo: open. Change before using for real company work.
  }

  enabled_cluster_log_types = []
  # Cluster logging disabled to save CloudWatch costs ($0.50/GB ingested).
  # Production: enable ["api", "audit", "authenticator"] at minimum.
  # "audit" logs every kubectl command — essential for security forensics.

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_subnet.private,
    aws_subnet.public,
  ]
  # Terraform dependency ordering.
  # EKS cluster needs its IAM role policy attached BEFORE cluster creation.
  # Otherwise cluster creation fails with "IAM role not ready".

  tags = local.common_tags
}

# ── EKS ADD-ONS ────────────────────────────────────────────────
# Add-ons are components that run inside the cluster.
# AWS manages their lifecycle — install, update, patch.
# Without these, the cluster won't function properly.

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"
  # WHY COREDNS:
  # CoreDNS is the DNS server inside Kubernetes.
  # When cart service calls "http://product-service:80",
  # CoreDNS resolves "product-service" to the Service's ClusterIP.
  # Without CoreDNS: service discovery breaks. Nothing talks to anything.

  depends_on = [aws_eks_node_group.spot]
  # CoreDNS pods need nodes to run on.
  # Add-on can't schedule until node group exists.
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
  # WHY KUBE-PROXY:
  # Runs on every node. Manages iptables rules.
  # When you send traffic to a Service ClusterIP, kube-proxy's rules
  # intercept it and route to one of the healthy pods.
  # Without kube-proxy: Services don't work. All traffic is dropped.

  depends_on = [aws_eks_node_group.spot]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
  # WHY VPC-CNI:
  # Assigns REAL VPC IP addresses to pods.
  # Without this: pods would need an overlay network (like Flannel).
  # With VPC-CNI: each pod gets a real VPC IP. Direct connectivity.
  # Benefits: pods can talk to other AWS services (RDS, ElastiCache)
  # without NAT or extra network hops.
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.main.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn
  # WHY EBS CSI:
  # Allows pods to use EBS volumes as persistent storage.
  # When Prometheus needs to store metrics to disk, it uses a
  # PersistentVolumeClaim. EBS CSI driver automatically provisions
  # an EBS volume and mounts it to the pod.
  # Without this: StatefulSets and PVCs don't work.

  depends_on = [aws_eks_node_group.spot]
}

# EBS CSI needs its own IAM role for IRSA
resource "aws_iam_role" "ebs_csi" {
  name = "${local.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.eks.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ── OIDC PROVIDER FOR THE EKS CLUSTER (for IRSA) ──────────────
# WHAT IS IRSA:
# IAM Roles for Service Accounts. Allows pods to have their own IAM role.
# WITHOUT IRSA: All pods on a node share the node's IAM role.
#   If one pod is compromised, attacker gets ALL node permissions.
# WITH IRSA: Cart pods can only access cart's secrets.
#   Payment pods can only access payment's secrets.
#   Principle of least privilege per pod.
#
# HOW IT WORKS:
# 1. EKS creates an OIDC provider (token issuer)
# 2. You create an IAM role with trust: "trust tokens from THIS cluster,
#    from THIS K8s namespace, from THIS service account"
# 3. K8s mounts a JWT into the pod
# 4. Pod exchanges JWT → AWS STS → 15-minute credentials
# 5. No static secrets anywhere in the pod

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
  # Fetches the EKS cluster's OIDC certificate thumbprint
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = local.common_tags
}

# ── NODE GROUP ─────────────────────────────────────────────────
resource "aws_eks_node_group" "spot" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-spot"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id
  # Nodes in PRIVATE subnets. Never directly reachable from internet.

  instance_types = var.node_instance_types
  # ["t3.medium", "t3a.medium"]: if AWS runs out of t3.medium spot
  # capacity in your AZ, it tries t3a.medium. Reduces interruption risk.
  # t3.medium = 2 vCPU, 4GB RAM: enough for 5 services + system pods.

  capacity_type = "SPOT"
  # SPOT = use spare AWS capacity at 60-80% discount.
  # Risk: AWS can reclaim with 2-minute warning.
  # Kubernetes handles this: receives the interruption notice,
  # drains the node, reschedules pods on another node.
  # For a demo cluster: acceptable. For prod stateful workloads: use ON_DEMAND.

  disk_size = var.node_disk_size
  # 20GB EBS volume per node. Our images are ~130MB each × 5 = 650MB.
  # System pods add ~500MB. 20GB is very comfortable.

  scaling_config {
    desired_size = var.node_desired_size # 1 node to start
    min_size     = var.node_min_size     # never go below 1
    max_size     = var.node_max_size     # never go above 3
    # Cluster Autoscaler reads min/max from these values.
    # When HPA wants more pods but no node has capacity,
    # CA adds a new node (up to max_size).
    # When nodes are underutilized, CA removes them (down to min_size).
  }

  update_config {
    max_unavailable = 1
    # During a node group update (K8s upgrade, AMI change):
    # take down at most 1 node at a time.
    # Prevents all nodes going down simultaneously during maintenance.
  }

  labels = {
    role        = "spot-worker"
    environment = var.environment
  }
  # Node labels. Used in pod scheduling:
  # nodeSelector: { role: spot-worker } → only schedule on these nodes.

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_readonly,
    aws_iam_role_policy_attachment.ssm_core,
  ]
  # Terraform: create node group ONLY after all IAM policies are attached.
  # If node group is created first, nodes start without ECR pull permission
  # and pods get ImagePullBackOff immediately.

  tags = local.common_tags
}

# ── AWS AUTH CONFIGMAP ─────────────────────────────────────────
# WHY THIS EXISTS:
# EKS uses the aws-auth ConfigMap to map IAM principals → K8s RBAC groups.
# By default: ONLY the IAM entity that created the cluster has access.
# That means: if Terraform creates the cluster, only Terraform's role
# can run kubectl commands. You can't kubectl from your laptop yet.
#
# This ConfigMap grants YOUR IAM user kubectl access to the cluster.
# system:masters = cluster-admin (full access). Use more restricted
# groups in production (system:basic-user for developers, etc.)
resource "aws_eks_access_entry" "admin" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = var.your_iam_user_arn
#  kubernetes_groups = ["system:masters"]
  type              = "STANDARD"
  # STANDARD = regular IAM user/role
  # After this: aws eks update-kubeconfig → kubectl commands work for you
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.your_iam_user_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# Also grant GitHub Actions kubectl access
resource "aws_eks_access_entry" "github_actions" {
  cluster_name      = aws_eks_cluster.main.name
  principal_arn     = aws_iam_role.github_actions.arn
#  kubernetes_groups = ["system:masters"]
  type              = "STANDARD"
  # GitHub Actions needs to run: kubectl rollout status, helm upgrade, etc.
  # In production: create a more restricted K8s role that only allows
  # deploying to the ecommerce namespace.
}

resource "aws_eks_access_policy_association" "github_actions" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = aws_iam_role.github_actions.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
