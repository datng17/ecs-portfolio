data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  service_name  = "${var.name_prefix}-app"
  log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.log_group_name}"

  # Valid Fargate memory sizes (MiB) per CPU size, for the sizes this workload may use.
  fargate_memory = {
    256  = [512, 1024, 2048]
    512  = [1024, 2048, 3072, 4096]
    1024 = [2048, 3072, 4096, 5120, 6144, 7168, 8192]
  }

  # Volume names: "/var/cache/nginx" -> "var-cache-nginx".
  writable_volumes = { for p in var.writable_paths : trim(replace(p, "/", "-"), "-") => p }

  container_definitions = [
    {
      name      = var.container_name
      image     = var.container_image
      essential = true
      user      = var.container_user

      readonlyRootFilesystem = true
      linuxParameters = {
        initProcessEnabled = true # Reaps zombies and forwards SIGTERM to nginx.
        capabilities       = { add = [], drop = ["ALL"] }
      }

      # ECS returns these as empty lists. Declaring them keeps the plan clean
      # (otherwise every plan shows a diff that forces a new task definition).
      environment    = []
      systemControls = []
      volumesFrom    = []

      portMappings = [{
        name          = "http"
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]

      mountPoints = [for name, path in local.writable_volumes : {
        sourceVolume  = name
        containerPath = path
        readOnly      = false
      }]

      # Same probe as the image HEALTHCHECK. busybox wget ships in the image.
      healthCheck = {
        command     = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:${var.container_port}${var.health_check_path}"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 10
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = local.region
          awslogs-stream-prefix = var.container_name
          # A slow CloudWatch API must not block nginx writes to stdout.
          mode            = "non-blocking"
          max-buffer-size = "25m"
        }
      }

      stopTimeout = 30
    },
  ]
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  tags = { Name = var.cluster_name }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}

# ---------------------------------------------------------------------------
# Container logs (KMS-encrypted). The execution role writes only to this group.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "logs_kms" {
  # checkov:skip=CKV_AWS_109:Key policies must use Resource "*" (it means this key). Root statement is the AWS default.
  # checkov:skip=CKV_AWS_111:Key policies must use Resource "*" (it means this key). Root statement is the AWS default.
  # checkov:skip=CKV_AWS_356:Key policies must use Resource "*" (it means this key).
  statement {
    sid       = "EnableRootAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # CloudWatch Logs may use the key only for the app log group.
  statement {
    sid    = "AllowCloudWatchLogsForAppLogGroup"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.log_group_arn]
    }
  }
}

resource "aws_kms_key" "logs" {
  description             = "${var.name_prefix} ECS container logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.logs_kms.json
  tags                    = { Name = "${var.name_prefix}-ecs-logs-kms" }
}

resource "aws_kms_alias" "logs" {
  name          = "alias/${var.name_prefix}-ecs-logs"
  target_key_id = aws_kms_key.logs.key_id
}

resource "aws_cloudwatch_log_group" "app" {
  # checkov:skip=CKV_AWS_338:Retention is set per environment (dev 14 days, prod 90 days) to control cost; 1 year is not required for this workload.
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
}

# ---------------------------------------------------------------------------
# Task definition (first revision; the CD pipeline registers the next ones)
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.task_cpu)
  memory                   = tostring(var.task_memory)
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = var.cpu_architecture
  }

  # Task-local ephemeral storage (no host path on Fargate). The image declares the same paths as
  # VOLUME, so Fargate copies their contents and ownership; otherwise the mount is root-owned 0755
  # and UID 101 couldn't write the nginx pid and cache files.
  dynamic "volume" {
    for_each = local.writable_volumes
    content {
      name = volume.key
    }
  }

  container_definitions = jsonencode(local.container_definitions)

  tags = { Name = var.task_family }

  lifecycle {
    precondition {
      condition     = contains(keys(local.fargate_memory), tostring(var.task_cpu)) && contains(lookup(local.fargate_memory, tostring(var.task_cpu), []), var.task_memory)
      error_message = "task_cpu/task_memory is not a valid Fargate combination (for 256 CPU: 512, 1024 or 2048 MiB)."
    }
    precondition {
      condition     = var.execution_role_arn != var.task_role_arn
      error_message = "The task role and the execution role must be different roles."
    }
  }
}

# ---------------------------------------------------------------------------
# Service security group: only the ALB reaches the container port
# ---------------------------------------------------------------------------
resource "aws_security_group" "service" {
  name        = "${var.name_prefix}-ecs-sg"
  description = "ECS tasks: ${var.container_port}/tcp from the ALB only, HTTPS egress"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.name_prefix}-ecs-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "App port from the ALB security group"
  ip_protocol                  = "tcp"
  from_port                    = var.container_port
  to_port                      = var.container_port
  referenced_security_group_id = var.alb_security_group_id
}

# HTTPS out only: ECR API and image layers (S3 gateway endpoint or NAT), CloudWatch Logs.
# DNS goes to the VPC resolver, which security groups don't filter.
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS to AWS APIs (ECR, S3, CloudWatch Logs)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
# ECS refuses a target group that no listener or rule forwards to. The default HTTPS action is
# a fixed 403, so the service must wait for the origin-verified rule, not just the listener.
resource "terraform_data" "load_balancer_ready" {
  input = var.load_balancer_dependencies
}

resource "aws_ecs_service" "this" {
  name             = local.service_name
  cluster          = aws_ecs_cluster.this.arn
  task_definition  = aws_ecs_task_definition.this.arn
  desired_count    = var.min_capacity
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent
  deployment_maximum_percent         = var.deployment_maximum_percent

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_controller {
    type = "ECS"
  }

  availability_zone_rebalancing = "ENABLED"
  enable_ecs_managed_tags       = true
  propagate_tags                = "SERVICE"
  enable_execute_command        = false
  wait_for_steady_state         = var.wait_for_steady_state

  tags = { Name = local.service_name }

  # Ownership split: Terraform creates the service and the first revision; CD owns task
  # definition revisions and Application Auto Scaling owns the task count.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
    precondition {
      condition     = var.max_capacity >= var.min_capacity
      error_message = "max_capacity must be greater than or equal to min_capacity."
    }
  }

  depends_on = [
    terraform_data.load_balancer_ready,
    aws_cloudwatch_log_group.app, # The first task must find its log group.
    aws_ecs_cluster_capacity_providers.this,
  ]
}

# ---------------------------------------------------------------------------
# Autoscaling: target tracking on CPU and on ALB requests per target
# ---------------------------------------------------------------------------
resource "aws_appautoscaling_target" "service" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_capacity
  max_capacity       = var.max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.service_name}-cpu-${var.cpu_target_percent}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service.service_namespace
  scalable_dimension = aws_appautoscaling_target.service.scalable_dimension
  resource_id        = aws_appautoscaling_target.service.resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.cpu_target_percent
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
}

resource "aws_appautoscaling_policy" "requests" {
  name               = "${local.service_name}-requests-per-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.service.service_namespace
  scalable_dimension = aws_appautoscaling_target.service.scalable_dimension
  resource_id        = aws_appautoscaling_target.service.resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = var.request_count_resource_label
    }
    target_value       = var.request_count_target
    scale_out_cooldown = var.scale_out_cooldown
    scale_in_cooldown  = var.scale_in_cooldown
  }
}
