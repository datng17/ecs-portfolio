variable "name_prefix" {
  description = "Prefix for resource names, for example portfolio-dev. ALB and target group names must stay within 32 characters."
  type        = string
  validation {
    condition     = length(var.name_prefix) <= 28
    error_message = "name_prefix must be at most 28 characters (ALB and target group names are limited to 32)."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC that holds the ALB and its targets."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. ALB egress is limited to this range on the target port."
  type        = string
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB, one per AZ (at least 2)."
  type        = list(string)
  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least 2 AZs."
  }
}

variable "cloudflare_ipv4_url" {
  description = "Cloudflare's published IPv4 ranges (one CIDR per line). The ALB security group allows only these."
  type        = string
  default     = "https://www.cloudflare.com/ips-v4"
}

# ---------------------------------------------------------------------------
# TLS
# ---------------------------------------------------------------------------
variable "certificate_domain" {
  description = "Domain of the existing ACM certificate in this region. The HTTPS listener requires it to be ISSUED."
  type        = string
}

variable "ssl_policy" {
  description = "HTTPS listener security policy. TLS 1.3 + TLS 1.2 (AEAD ciphers only) so Cloudflare can connect with either."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  validation {
    condition     = startswith(var.ssl_policy, "ELBSecurityPolicy-TLS13-")
    error_message = "ssl_policy must be a TLS 1.3 policy (ELBSecurityPolicy-TLS13-*)."
  }
}

# ---------------------------------------------------------------------------
# Origin protection (Cloudflare Transform Rule adds the header, the ALB checks it)
# ---------------------------------------------------------------------------
variable "origin_verify_header_name" {
  description = "Request header Cloudflare adds to every proxied request. Requests without the right value get 403."
  type        = string
  default     = "X-Origin-Verify"
}

variable "origin_secret_parameter_name" {
  description = "SSM SecureString parameter that holds the header value. null means /<name_prefix>/alb/origin-verify-secret."
  type        = string
  default     = null
}

variable "origin_secret_version" {
  description = "Change this value to generate a new origin secret (rotation). Update the Cloudflare Transform Rule right after apply."
  type        = string
  default     = "1"
}

variable "ssm_kms_key_id" {
  description = "KMS key for the SecureString parameter. null means the AWS-managed alias/aws/ssm key."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Load balancer and target group
# ---------------------------------------------------------------------------
variable "enable_deletion_protection" {
  description = "ALB deletion protection. On in prod, off in dev so teardown works."
  type        = bool
  default     = true
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds."
  type        = number
  default     = 60
}

variable "target_port" {
  description = "Container port the target group sends traffic to (nginx-unprivileged listens on 8080)."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Target group health check path."
  type        = string
  default     = "/healthz"
}

variable "deregistration_delay" {
  description = "Seconds the target group drains a deregistering task. Requests to a static site finish in well under a second."
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Access logs
# ---------------------------------------------------------------------------
variable "access_logs_prefix" {
  description = "Key prefix for access logs in the bucket. Must not contain AWSLogs."
  type        = string
  default     = "alb"
  validation {
    condition     = !strcontains(var.access_logs_prefix, "AWSLogs") && !startswith(var.access_logs_prefix, "/") && !endswith(var.access_logs_prefix, "/")
    error_message = "access_logs_prefix must not contain AWSLogs or start/end with a slash."
  }
}

variable "access_logs_retention_days" {
  description = "Days to keep ALB access log objects."
  type        = number
  default     = 14
  validation {
    condition     = var.access_logs_retention_days >= 1
    error_message = "access_logs_retention_days must be at least 1."
  }
}

variable "access_logs_force_destroy" {
  description = "Let terraform destroy delete the access log bucket with objects in it. true in dev, false in prod."
  type        = bool
  default     = false
}
