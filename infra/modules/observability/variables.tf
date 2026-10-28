variable "name_prefix" {
  description = "Prefix for resource names, for example portfolio-dev."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the alerts topic (and sent budget alerts). Keep it in the gitignored terraform.tfvars only."
  type        = string
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must be an email address."
  }
}

# ---------------------------------------------------------------------------
# Metric dimensions (from the ALB and ECS modules)
# ---------------------------------------------------------------------------
variable "alb_arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>), the LoadBalancer dimension."
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix (targetgroup/<name>/<id>), the TargetGroup dimension."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster name, the ClusterName dimension."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service name, the ServiceName dimension."
  type        = string
}

variable "ecs_min_capacity" {
  description = "Minimum task count, drawn as a reference line on the dashboard."
  type        = number
  default     = 2
}

variable "ecs_max_capacity" {
  description = "Maximum task count, drawn as a reference line on the dashboard."
  type        = number
  default     = 5
}

# ---------------------------------------------------------------------------
# Alarm evaluation: every alarm uses 1-minute periods and fires on M of N datapoints.
# ---------------------------------------------------------------------------
variable "alarm_period_seconds" {
  description = "Period of each alarm datapoint in seconds."
  type        = number
  default     = 60
  validation {
    condition     = contains([10, 30, 60, 300], var.alarm_period_seconds)
    error_message = "alarm_period_seconds must be 10, 30, 60 or 300."
  }
}

variable "alarm_evaluation_periods" {
  description = "N: number of datapoints evaluated."
  type        = number
  default     = 5
}

variable "alarm_datapoints_to_alarm" {
  description = "M: breaching datapoints (out of N) that put the alarm in ALARM."
  type        = number
  default     = 3
  validation {
    condition     = var.alarm_datapoints_to_alarm >= 1 && var.alarm_datapoints_to_alarm <= var.alarm_evaluation_periods
    error_message = "alarm_datapoints_to_alarm must be between 1 and alarm_evaluation_periods."
  }
}

# ---------------------------------------------------------------------------
# Thresholds (SLOs: p95 < 300 ms, error rate < 0.1 %, availability 99.9 %)
# ---------------------------------------------------------------------------
variable "elb_5xx_threshold" {
  description = "ALB-generated 5xx responses per period (502/503/504: no healthy target, target timeout or reset)."
  type        = number
  default     = 5
}

variable "target_5xx_rate_threshold_percent" {
  description = "Target 5xx responses as a percentage of requests per period."
  type        = number
  default     = 1
}

variable "target_5xx_min_requests" {
  description = "Ignore the target 5xx rate in periods with fewer requests than this (one error in 3 requests isn't an outage)."
  type        = number
  default     = 20
}

variable "unhealthy_host_threshold" {
  description = "Unhealthy targets (Maximum per period) that count as breaching."
  type        = number
  default     = 1
}

variable "latency_p95_threshold_seconds" {
  description = "p95 TargetResponseTime threshold in seconds (SLO: 300 ms)."
  type        = number
  default     = 0.3
}

variable "cpu_threshold_percent" {
  description = "Average service CPU threshold. Autoscaling targets 60 %, so a sustained 80 % means scaling isn't keeping up."
  type        = number
  default     = 80
}

variable "memory_threshold_percent" {
  description = "Average service memory threshold. Memory isn't a scaling metric, so this catches leaks and undersized tasks."
  type        = number
  default     = 80
}

# ---------------------------------------------------------------------------
# Budget (account-wide, see PROGRESS.md B-3)
# ---------------------------------------------------------------------------
variable "create_budget" {
  description = "Create the monthly cost budget. It's account-wide (cost allocation tags can't be activated from this linked account), so enable it in exactly one environment stack."
  type        = bool
  default     = false
}

variable "budget_name" {
  description = "Budget name. null means <name_prefix>-monthly-cost."
  type        = string
  default     = null
}

variable "budget_limit_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 30
  validation {
    condition     = var.budget_limit_usd > 0
    error_message = "budget_limit_usd must be positive."
  }
}

variable "budget_actual_thresholds_percent" {
  description = "Alert when ACTUAL spend passes each of these percentages of the budget."
  type        = list(number)
  default     = [50, 80, 100]
}

variable "budget_forecast_thresholds_percent" {
  description = "Alert when FORECASTED spend passes each of these percentages of the budget."
  type        = list(number)
  default     = [100]
}

# ---------------------------------------------------------------------------
# KMS
# ---------------------------------------------------------------------------
variable "kms_deletion_window_days" {
  description = "Waiting period before the SNS CMK is deleted."
  type        = number
  default     = 7
  validation {
    condition     = var.kms_deletion_window_days >= 7 && var.kms_deletion_window_days <= 30
    error_message = "kms_deletion_window_days must be between 7 and 30."
  }
}
