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
  default     = "prod"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block (/16). Doesn't overlap dev (10.10.0.0/16), so the VPCs could be peered."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of AZs."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (true) or one per AZ (false). prod: one per AZ, so an AZ outage doesn't cut egress for the others."
  type        = bool
  default     = false
}

variable "enable_interface_endpoints" {
  description = "Create ECR/Logs interface endpoints, so image pulls and logs don't go through NAT."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 90
}

variable "ecr_force_delete" {
  description = "Let terraform destroy remove the ECR repository with images in it. false in prod."
  type        = bool
  default     = false
}

variable "certificate_domain" {
  description = "Domain of the existing ACM certificate (ap-southeast-2) used by the HTTPS listener. A real prod would have its own hostname and certificate."
  type        = string
  default     = "test.name.vn"
}

variable "origin_secret_version" {
  description = "Bump to rotate the X-Origin-Verify secret. Update the Cloudflare Transform Rule right after apply."
  type        = string
  default     = "1"
}

variable "alb_deletion_protection" {
  description = "ALB deletion protection. true in prod."
  type        = bool
  default     = true
}

variable "alb_logs_force_destroy" {
  description = "Let terraform destroy remove the ALB access log bucket with objects in it. false in prod."
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Image tag (git SHA) for the first task definition revision. CD rolls out later tags."
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
  description = "Target tracking: ALB requests per target per minute."
  type        = number
  default     = 1000
}

variable "alert_email" {
  description = "Receives SNS alarm notifications. Set it only in the gitignored terraform.tfvars."
  type        = string
}
