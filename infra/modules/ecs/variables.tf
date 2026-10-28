variable "name_prefix" {
  description = "Prefix for resource names, for example portfolio-dev."
  type        = string
}

# ---------------------------------------------------------------------------
# Naming contract with the IAM module (deploy roles are scoped by these names)
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "ECS cluster name. Must equal module.iam.ecs_cluster_name, which the deploy role is scoped to."
  type        = string
}

variable "log_group_name" {
  description = "Container log group. Must equal module.iam.app_log_group_name, the only group the execution role can write to."
  type        = string
  validation {
    condition     = startswith(var.log_group_name, "/")
    error_message = "log_group_name must start with a slash, for example /ecs/portfolio-dev."
  }
}

variable "task_family" {
  description = "Task definition family. Must start with module.iam.task_definition_family_prefix."
  type        = string
}

variable "execution_role_arn" {
  description = "Task execution role (ECR pull, log delivery)."
  type        = string
}

variable "task_role_arn" {
  description = "Task role used by the application. Must differ from the execution role."
  type        = string
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
variable "container_insights" {
  description = "Container Insights mode: enabled (standard metrics), enhanced (task/container level, costs more) or disabled."
  type        = string
  default     = "enabled"
  validation {
    condition     = contains(["enabled", "enhanced", "disabled"], var.container_insights)
    error_message = "container_insights must be enabled, enhanced or disabled."
  }
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
variable "container_name" {
  description = "Container name. The CD pipeline renders the image into this container."
  type        = string
  default     = "app"
}

variable "container_image" {
  description = "Image for the first task definition revision (<repo-url>:<git-sha>). CD registers later revisions."
  type        = string
  validation {
    condition     = can(regex("^[^\\s:]+(:[0-9]+)?/[^\\s:]+:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.container_image))
    error_message = "container_image must be <registry>/<repository>:<tag> with an explicit tag."
  }
}

variable "container_port" {
  description = "Port nginx-unprivileged listens on."
  type        = number
  default     = 8080
}

variable "container_user" {
  description = "UID:GID the container runs as (nginx-unprivileged is 101:101)."
  type        = string
  default     = "101:101"
  validation {
    condition     = can(regex("^[1-9][0-9]*(:[0-9]+)?$", var.container_user))
    error_message = "container_user must be a non-root numeric UID[:GID]."
  }
}

variable "writable_paths" {
  description = "Paths mounted as task-local ephemeral volumes, the only writable places under the read-only root filesystem. The image declares them as VOLUME so Fargate copies their ownership (UID 101)."
  type        = list(string)
  default     = ["/tmp", "/var/cache/nginx"]
}

variable "task_cpu" {
  description = "Task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task memory in MiB. Must be a valid Fargate combination with task_cpu."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "Fargate CPU architecture. ARM64 runs on Graviton (about 20% cheaper than X86_64)."
  type        = string
  default     = "ARM64"
  validation {
    condition     = contains(["ARM64", "X86_64"], var.cpu_architecture)
    error_message = "cpu_architecture must be ARM64 or X86_64."
  }
}

variable "health_check_path" {
  description = "Path probed by the container health check (same as the target group)."
  type        = string
  default     = "/healthz"
}

variable "log_retention_days" {
  description = "Retention of the container log group."
  type        = number
  default     = 14
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
variable "vpc_id" {
  description = "VPC for the service security group."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the tasks, one per AZ (at least 2)."
  type        = list(string)
  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "Use at least 2 private subnets so tasks run in 2 AZs."
  }
}

variable "alb_security_group_id" {
  description = "ALB security group. The service accepts container_port traffic from this group only."
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group (target_type ip) the service registers into."
  type        = string
}

variable "load_balancer_dependencies" {
  description = "ARNs (listener, listener rule) that must exist before the service is created. ECS rejects a target group that no listener or rule forwards to."
  type        = list(string)
  default     = []
}

variable "health_check_grace_period_seconds" {
  description = "Seconds ECS ignores failing ALB health checks after a task starts."
  type        = number
  default     = 30
}

variable "deployment_minimum_healthy_percent" {
  description = "Lower bound of running tasks during a deployment, in percent of desired."
  type        = number
  default     = 100
}

variable "deployment_maximum_percent" {
  description = "Upper bound of running tasks during a deployment, in percent of desired."
  type        = number
  default     = 200
}

variable "wait_for_steady_state" {
  description = "Make terraform apply wait until the service is stable."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------
variable "min_capacity" {
  description = "Minimum (and initial desired) task count."
  type        = number
  default     = 2
  validation {
    condition     = var.min_capacity >= 1
    error_message = "min_capacity must be at least 1."
  }
}

variable "max_capacity" {
  description = "Maximum task count."
  type        = number
  default     = 5
}

variable "cpu_target_percent" {
  description = "Target average service CPU utilisation (percent)."
  type        = number
  default     = 60
  validation {
    condition     = var.cpu_target_percent > 0 && var.cpu_target_percent <= 100
    error_message = "cpu_target_percent must be in (0, 100]."
  }
}

variable "request_count_resource_label" {
  description = "app/<alb>/<id>/targetgroup/<tg>/<id> for ALBRequestCountPerTarget (module.alb.alb_request_count_resource_label)."
  type        = string
}

variable "request_count_target" {
  description = "Target ALB requests per target per minute. Tuned in Task 14."
  type        = number
  default     = 1000
  validation {
    condition     = var.request_count_target > 0
    error_message = "request_count_target must be positive."
  }
}

variable "scale_out_cooldown" {
  description = "Seconds after a scale-out before another scale-out."
  type        = number
  default     = 60
}

variable "scale_in_cooldown" {
  description = "Seconds after a scale-in before another scale-in."
  type        = number
  default     = 300
}
