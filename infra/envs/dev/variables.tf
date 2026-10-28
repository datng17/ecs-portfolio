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
