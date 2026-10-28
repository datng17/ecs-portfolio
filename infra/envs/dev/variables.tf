variable "account_id" {
  description = "AWS account for this environment. The provider refuses any other account."
  type        = string
  default     = "681990781993"
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-2"
}

variable "project" {
  description = "Project name, used in resource names and the Project tag."
  type        = string
  default     = "portfolio"
}

variable "env" {
  description = "Environment name, used in resource names and the Env tag."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block (/16)."
  type        = string
  default     = "10.10.0.0/16"
}

variable "az_count" {
  description = "Number of AZs."
  type        = number
  default     = 2
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (true) or one per AZ (false)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create ECR/Logs interface endpoints. Off in dev to save about $44/month."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 14
}

variable "ecr_force_delete" {
  description = "Let terraform destroy remove the ECR repository with images in it. true in dev, false in prod."
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN. Created by the org admin (SCP blocks it here, see B-1); not created or read by Terraform."
  type        = string
  default     = "arn:aws:iam::681990781993:oidc-provider/token.actions.githubusercontent.com"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) trusted by the OIDC roles."
  type        = string
  default     = "datng17/ecs-portfolio"
}

variable "certificate_domain" {
  description = "Domain of the existing ACM certificate (ap-southeast-2) used by the HTTPS listener."
  type        = string
  default     = "test.name.vn"
}

variable "origin_secret_version" {
  description = "Bump to rotate the X-Origin-Verify secret. Update the Cloudflare Transform Rule right after apply."
  type        = string
  default     = "1"
}

variable "alb_deletion_protection" {
  description = "ALB deletion protection. false in dev (teardown), true in prod."
  type        = bool
  default     = false
}

variable "alb_logs_force_destroy" {
  description = "Let terraform destroy remove the ALB access log bucket with objects in it. true in dev, false in prod."
  type        = bool
  default     = true
}

variable "image_tag" {
  description = "Image tag (git SHA) for the first task definition revision. Push it to ECR before the full apply (Task 10). CD rolls out later tags."
  type        = string
  default     = "initial"
}

variable "ecs_min_capacity" {
  description = "Minimum (and initial) task count."
  type        = number
  default     = 2
}

variable "ecs_max_capacity" {
  description = "Maximum task count."
  type        = number
  default     = 5
}

variable "ecs_cpu_target_percent" {
  description = "Target tracking: average service CPU percent."
  type        = number
  default     = 60
}

variable "ecs_request_count_target" {
  description = "Target tracking: ALB requests per target per minute (tuned in Task 14)."
  type        = number
  default     = 1000
}

variable "alert_email" {
  description = "Receives SNS alarm notifications and budget alerts. Set it only in the gitignored terraform.tfvars."
  type        = string
}

variable "budget_limit_usd" {
  description = "Monthly account cost budget in USD (alerts at 50/80/100 % actual and 100 % forecast)."
  type        = number
  default     = 30
}
