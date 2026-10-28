data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  origin_secret_parameter_name = coalesce(var.origin_secret_parameter_name, "/${var.name_prefix}/alb/origin-verify-secret")

  access_logs_bucket_name = "${var.name_prefix}-alb-logs-${local.account_id}-${local.region}"

  # One CIDR per line; ignore blank lines and CRLF.
  cloudflare_ipv4_cidrs = sort(distinct(compact([
    for line in split("\n", replace(data.http.cloudflare_ipv4.response_body, "\r", "")) : trimspace(line)
  ])))

  # Cloudflare (Full strict) connects on 443. Port 80 only returns a redirect to 443.
  alb_ingress = {
    for pair in setproduct([80, 443], local.cloudflare_ipv4_cidrs) :
    "${pair[0]}-${pair[1]}" => { port = pair[0], cidr = pair[1] }
  }
}

# ---------------------------------------------------------------------------
# Cloudflare IPv4 ranges
# ---------------------------------------------------------------------------
data "http" "cloudflare_ipv4" {
  url             = var.cloudflare_ipv4_url
  request_headers = { Accept = "text/plain" }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "Fetching the Cloudflare IPv4 list failed (HTTP status is not 200)."
    }
  }
}

# ---------------------------------------------------------------------------
# Security group: Cloudflare IPv4 ranges only, egress only to targets
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB: HTTP/HTTPS from Cloudflare IPv4 ranges only"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-alb-sg" }

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(local.cloudflare_ipv4_cidrs) > 0
      error_message = "The Cloudflare IPv4 list is empty; refusing to create an ALB security group with no allowed sources."
    }
    precondition {
      condition     = alltrue([for c in local.cloudflare_ipv4_cidrs : can(cidrhost(c, 0)) && strcontains(c, "/")])
      error_message = "The Cloudflare IPv4 list contains an entry that is not a CIDR block."
    }
    precondition {
      # Default quota is 60 inbound rules per security group.
      condition     = length(local.alb_ingress) <= 60
      error_message = "Too many Cloudflare ranges for one security group (more than 60 inbound rules)."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "cloudflare" {
  for_each = local.alb_ingress

  security_group_id = aws_security_group.alb.id
  description       = "Cloudflare ${each.value.cidr} on ${each.value.port}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr
  tags              = { Name = "${var.name_prefix}-alb-cf-${each.value.port}" }
}

resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.alb.id
  description       = "Traffic and health checks to targets in the VPC"
  ip_protocol       = "tcp"
  from_port         = var.target_port
  to_port           = var.target_port
  cidr_ipv4         = var.vpc_cidr
}

# ---------------------------------------------------------------------------
# ACM certificate (existing, not managed here)
# ---------------------------------------------------------------------------
data "aws_acm_certificate" "this" {
  domain      = var.certificate_domain
  most_recent = true
  # Look up every status so the listener precondition can report a non-ISSUED cert clearly,
  # instead of the data source failing with "no certificate found".
  statuses  = ["ISSUED", "PENDING_VALIDATION", "INACTIVE", "EXPIRED", "VALIDATION_TIMED_OUT", "REVOKED", "FAILED"]
  key_types = ["RSA_2048", "RSA_3072", "RSA_4096", "EC_prime256v1", "EC_secp384r1"]
}

# ---------------------------------------------------------------------------
# Origin secret (header value Cloudflare adds) in SSM SecureString
# ---------------------------------------------------------------------------
# Alphanumeric only: ALB header conditions treat * and ? as wildcards. 48 chars ~ 285 bits.
resource "random_password" "origin_secret" {
  length  = 48
  special = false

  keepers = {
    version = var.origin_secret_version
  }
}

resource "aws_ssm_parameter" "origin_secret" {
  # checkov:skip=CKV_AWS_337:Uses the AWS-managed alias/aws/ssm key (no $1/month CMK), same choice as ECR and the state bucket. Set ssm_kms_key_id for a CMK.
  name        = local.origin_secret_parameter_name
  description = "Value of the ${var.origin_verify_header_name} header that Cloudflare adds. The ALB forwards only requests that carry it."
  type        = "SecureString"
  tier        = "Standard"
  key_id      = var.ssm_kms_key_id
  value       = random_password.origin_secret.result
}

# ---------------------------------------------------------------------------
# Access log bucket (ALB log delivery supports SSE-S3 only)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "access_logs" {
  # checkov:skip=CKV_AWS_145:ALB access log delivery supports only SSE-S3 (AES256), not SSE-KMS.
  # checkov:skip=CKV_AWS_18:This bucket is itself a log destination; logging it would need another bucket for no benefit.
  # checkov:skip=CKV_AWS_144:Cross-region replication doubles cost for short-lived access logs.
  # checkov:skip=CKV2_AWS_62:No consumer for event notifications; logs are queried ad hoc.
  bucket        = local.access_logs_bucket_name
  force_destroy = var.access_logs_force_destroy
  tags          = { Name = local.access_logs_bucket_name }
}

resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "expire-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.access_logs_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.access_logs]
}

data "aws_iam_policy_document" "access_logs" {
  # Current AWS-recommended form: the log delivery service principal, with this account's ID in the path
  # so only load balancers in this account can write here.
  statement {
    sid       = "AllowAlbLogDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/${var.access_logs_prefix}/AWSLogs/${local.account_id}/*"]
    principals {
      type        = "Service"
      identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
    }
  }

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

# ---------------------------------------------------------------------------
# Load balancer
# ---------------------------------------------------------------------------
resource "aws_lb" "this" {
  # checkov:skip=CKV2_AWS_28:Cloudflare's WAF filters traffic at the edge and the security group admits only Cloudflare; AWS WAF would add ~$10+/month for the same layer.
  # checkov:skip=CKV_AWS_150:Deletion protection is driven by enable_deletion_protection: on in prod, off in dev so teardown (Task 18) works.
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  ip_address_type    = "ipv4"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  drop_invalid_header_fields = true
  desync_mitigation_mode     = "defensive"
  enable_http2               = true
  idle_timeout               = var.idle_timeout
  enable_deletion_protection = var.enable_deletion_protection

  access_logs {
    enabled = true
    bucket  = aws_s3_bucket.access_logs.id
    prefix  = var.access_logs_prefix
  }

  tags = { Name = "${var.name_prefix}-alb" }

  # ELB writes a test object when logging is enabled, so the policy and encryption must exist first.
  depends_on = [
    aws_s3_bucket_policy.access_logs,
    aws_s3_bucket_server_side_encryption_configuration.access_logs,
    aws_s3_bucket_ownership_controls.access_logs,
  ]
}

resource "aws_lb_target_group" "app" {
  # checkov:skip=CKV_AWS_378:TLS terminates at the ALB; targets are in private subnets and reachable only from the ALB security group, so ALB->task traffic is plain HTTP on 8080.
  name                 = "${var.name_prefix}-tg"
  target_type          = "ip" # Fargate awsvpc tasks register by IP.
  protocol             = "HTTP"
  protocol_version     = "HTTP1"
  port                 = var.target_port
  vpc_id               = var.vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.name_prefix}-tg" }
}

# --- :80 -> 301 to :443 -------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# --- :443, default 403 ----------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = var.ssl_policy
  certificate_arn   = data.aws_acm_certificate.this.arn

  # Anything that doesn't match a rule (no or wrong origin header, e.g. direct hits on the ALB DNS name) gets 403.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  lifecycle {
    precondition {
      condition     = data.aws_acm_certificate.this.status == "ISSUED"
      error_message = "ACM certificate for ${var.certificate_domain} is ${data.aws_acm_certificate.this.status}, not ISSUED."
    }
  }
}

# Forward only requests that carry the origin secret header (added by the Cloudflare Transform Rule).
resource "aws_lb_listener_rule" "origin_verified" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  condition {
    http_header {
      http_header_name = var.origin_verify_header_name
      values           = [aws_ssm_parameter.origin_secret.value]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = { Name = "${var.name_prefix}-origin-verified" }
}
