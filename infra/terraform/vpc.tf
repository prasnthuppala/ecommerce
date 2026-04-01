# =============================================================
# vpc.tf
# =============================================================
# WHY A VPC:
# A VPC is your private, isolated network inside AWS.
# Without one, every EC2 instance would be on AWS's shared public
# network — reachable from anywhere on the internet.
#
# Our VPC layout:
#
#  VPC: 10.0.0.0/16
#  ┌─────────────────────────────────────────────────────┐
#  │  AZ: ap-south-1a          AZ: ap-south-1b           │
#  │  ┌──────────────┐        ┌──────────────┐           │
#  │  │ Public subnet│        │ Public subnet│           │
#  │  │ 10.0.101.0/24│        │ 10.0.102.0/24│          │
#  │  │ [ALB lives   │        │ [NAT GW here]│          │
#  │  │  here]       │        │              │           │
#  │  └──────┬───────┘        └──────┬───────┘           │
#  │         │ NAT                   │                    │
#  │  ┌──────▼───────┐        ┌──────▼───────┐           │
#  │  │Private subnet│        │Private subnet│           │
#  │  │ 10.0.1.0/24  │        │ 10.0.2.0/24  │          │
#  │  │ [EKS nodes   │        │ [EKS nodes   │           │
#  │  │  live here]  │        │  live here]  │           │
#  │  └──────────────┘        └──────────────┘           │
#  └─────────────────────────────────────────────────────┘
#       │
#  Internet Gateway ← only public subnets have a route here
#
# WHY NODES IN PRIVATE SUBNETS:
# Private = no direct internet route. Nodes cannot be SSH'd into
# from the internet. Attack surface is dramatically reduced.
# Nodes reach internet (for ECR image pulls) via NAT Gateway.
# NAT = outbound only. Nobody from internet can reach the nodes.
# =============================================================

# ── VPC ────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  # WHY DNS HOSTNAMES + SUPPORT:
  # EKS requires DNS to work. Nodes register themselves with the
  # control plane using their DNS hostname. Without this, nodes
  # can't join the cluster.

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-vpc"
  })
}

# ── Internet Gateway ───────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  # The Internet Gateway is the door between your VPC and the internet.
  # Only public subnets have a route to this gateway.
  # Private subnets use NAT Gateway instead (outbound only).

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-igw" })
}

# ── Public Subnets ─────────────────────────────────────────────
resource "aws_subnet" "public" {
  count             = length(var.public_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]
  # count = 2: creates 2 public subnets, one per AZ
  # count.index = 0, 1: used to pick the right CIDR and AZ

  map_public_ip_on_launch = true
  # Resources launched in public subnet automatically get a public IP.
  # Needed for: Load Balancers to be reachable from internet.

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-public-${local.azs[count.index]}"
    # K8s tag: tells AWS Load Balancer Controller to create
    # internet-facing ALBs in these subnets
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  })
}

# ── Private Subnets ────────────────────────────────────────────
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  # No map_public_ip_on_launch — private subnets never get public IPs

  tags = merge(local.common_tags, {
    Name = "${local.cluster_name}-private-${local.azs[count.index]}"
    # K8s tag: tells AWS LB Controller to create internal ALBs here
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  })
}

# ── NAT Gateway ────────────────────────────────────────────────
# WHY NAT GATEWAY:
# Private subnet nodes need to reach the internet to:
#   - Pull Docker images from ECR
#   - Call AWS APIs (IRSA token exchange, Secrets Manager, etc.)
#   - Download OS patches
# But we DON'T want internet to reach the nodes.
# NAT = Network Address Translation. Allows OUTBOUND traffic from
# private subnets, blocks all INBOUND traffic. One-way door.
#
# ONE NAT vs ONE PER AZ:
# Production: one NAT per AZ. If AZ-a NAT fails, AZ-b nodes still work.
# Our portfolio dev: one NAT in public subnet of AZ-a.
# Risk: if AZ-a goes down (rare), AZ-b nodes lose internet.
# Savings: ~$32/month per extra NAT. Not worth it for a demo cluster.
resource "aws_eip" "nat" {
  domain = "vpc"
  # EIP = Elastic IP. A static public IP address.
  # The NAT Gateway needs a fixed public IP so AWS can route return traffic.

  depends_on = [aws_internet_gateway.main]
  # NAT gateway needs Internet Gateway to exist first.
  # depends_on makes Terraform wait for IGW before creating EIP.

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  # NAT Gateway lives in a PUBLIC subnet (it needs to reach internet)
  # but serves traffic FROM private subnets.

  depends_on = [aws_internet_gateway.main]

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-nat" })
}

# ── Route Tables ───────────────────────────────────────────────
# Route tables = routing rules for subnets.
# "Where does traffic with destination X go?"

# Public subnet route table: send 0.0.0.0/0 to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
    # 0.0.0.0/0 = "everything else" = default route
    # Send all non-VPC traffic to the Internet Gateway
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-public-rt" })
}

# Private subnet route table: send 0.0.0.0/0 to NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
    # Private subnets send outbound traffic to NAT Gateway
    # NAT Gateway translates private IP → public EIP → internet
    # Return traffic comes back through NAT → private IP. Invisible to internet.
  }

  tags = merge(local.common_tags, { Name = "${local.cluster_name}-private-rt" })
}

# Associate route tables with their subnets
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
  # Without associations: subnets use the VPC's default route table
  # which has no routes. Traffic goes nowhere. Pods can't reach internet.
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
