# =============================================================
# ecr.tf
# =============================================================
# WHY ECR AND NOT GITHUB CONTAINER REGISTRY (GHCR):
# Your CI pipeline (ci.yml) currently pushes to GHCR. That's fine
# for Minikube. For EKS, we switch to ECR because:
#
# 1. ZERO DATA TRANSFER COST: Pulling images from ECR to EKS in
#    the same region is FREE. Pulling from GHCR costs NAT egress.
#    Our 5 images × 130MB × N pod restarts = real money.
#
# 2. NO RATE LIMITS: GHCR has pull rate limits for free accounts.
#    During a rolling deploy, K8s pulls images frequently.
#    ECR = unlimited pulls from your own repos.
#
# 3. IAM INTEGRATION: ECR uses IAM for auth. Nodes can pull images
#    using their IAM role (ecr:read). No separate registry credentials.
#
# 4. ECR SCANNING: AWS automatically scans images for OS CVEs on push.
#    Second layer of security on top of Trivy in CI.
# =============================================================

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)
  # for_each creates one ECR repo per service name.
  # local.services = ["cart", "product", "payment", "auth", "notification"]
  # Creates:
  #   aws_ecr_repository.services["cart"]
  #   aws_ecr_repository.services["product"]  etc.

  name = "${var.project_name}/${each.key}"
  # Final names: devops-portfolio/cart, devops-portfolio/product, etc.
  # Namespace prefix groups your repos in ECR console. Easier to manage.

  image_tag_mutability = "MUTABLE"
  # MUTABLE: same tag (e.g. "latest") can be overwritten by a new push.
  # IMMUTABLE: once pushed, a tag is permanent. More secure but requires
  #            unique tags for every push (e.g. git SHA tags). We use both:
  #            SHA tag (immutable in practice) + latest tag (MUTABLE convenience).

  image_scanning_configuration {
    scan_on_push = true
    # Auto-scan every image on push using AWS's built-in CVE scanner.
    # This is ADDITIONAL to Trivy in your CI pipeline.
    # Two scanners = better coverage. AWS scanner checks OS packages.
    # Results appear in: ECR console → repo → Images → Vulnerabilities.
    # FREE with Basic scanning. Enhanced scanning = extra cost.
  }

  tags = merge(local.common_tags, {
    Service = each.key
  })
}

# ── ECR LIFECYCLE POLICY ───────────────────────────────────────
# WHY LIFECYCLE POLICIES:
# Without them, every docker push adds a new image. After 6 months
# of CI/CD, you have 1000+ images per repo.
# ECR charges $0.10/GB/month for storage.
# 1000 images × 130MB = 130GB × $0.10 = $13/month JUST for old images.
# Lifecycle policy: automatically delete images older than a threshold.
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
          # Keep the 10 most recent tagged images.
          # Older tagged images are deleted automatically.
          # "tagged" = images with a tag (like git SHA or version)
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
          # Untagged images = failed builds, intermediary layers.
          # They accumulate fast. Delete after 1 day. No value keeping them.
        }
        action = { type = "expire" }
      }
    ]
  })
}
