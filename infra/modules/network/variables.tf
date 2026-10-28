variable "name_prefix" {
  description = "Prefix for resource names, for example portfolio-dev."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be a /16 so each subnet can be a /20."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16 CIDR block."
  }
}

variable "az_count" {
  description = "Number of availability zones. One public and one private subnet are created in each."
  type        = number
  default     = 2
  validation {
    condition     = var.az_count >= 2 && var.az_count <= 4
    error_message = "az_count must be between 2 and 4 (the ALB needs at least 2 AZs)."
  }
}

variable "single_nat_gateway" {
  description = "true: one NAT gateway shared by all private subnets (cheaper). false: one NAT gateway per AZ (no cross-AZ dependency)."
  type        = bool
  default     = true
}

variable "enable_interface_endpoints" {
  description = "Create interface VPC endpoints (ECR, CloudWatch Logs, ...) so tasks don't pull through NAT. About $7.3/month per endpoint per AZ."
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "Service short names for interface endpoints, used when enable_interface_endpoints is true."
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "logs"]
}

variable "flow_log_retention_days" {
  description = "Retention in days for the VPC flow log group."
  type        = number
  default     = 14
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_log_retention_days)
    error_message = "flow_log_retention_days must be a value CloudWatch Logs accepts."
  }
}

variable "flow_log_traffic_type" {
  description = "Traffic captured by VPC flow logs: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"
  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ACCEPT, REJECT or ALL."
  }
}
