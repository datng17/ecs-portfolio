# Unit tests for the ECS module. No AWS credentials needed: the AWS provider is mocked.
#
#   cd infra/modules/ecs
#   terraform init -backend=false
#   terraform test

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      region = "ap-southeast-2"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name_prefix        = "portfolio-test"
  cluster_name       = "portfolio-test-cluster"
  log_group_name     = "/ecs/portfolio-test"
  task_family        = "portfolio-test-app"
  execution_role_arn = "arn:aws:iam::123456789012:role/portfolio-test-ecs-execution"
  task_role_arn      = "arn:aws:iam::123456789012:role/portfolio-test-ecs-task"
  container_image    = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/portfolio-test-app:0123abc"

  vpc_id                       = "vpc-0123456789abcdef0"
  private_subnet_ids           = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  alb_security_group_id        = "sg-0123456789abcdef0"
  target_group_arn             = "arn:aws:elasticloadbalancing:ap-southeast-2:123456789012:targetgroup/portfolio-test-tg/0123456789abcdef"
  request_count_resource_label = "app/portfolio-test-alb/0123456789abcdef/targetgroup/portfolio-test-tg/0123456789abcdef"
  load_balancer_dependencies   = ["arn:aws:elasticloadbalancing:ap-southeast-2:123456789012:listener-rule/app/portfolio-test-alb/0123456789abcdef/0123456789abcdef/0123456789abcdef"]
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------
run "cluster_has_container_insights" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "portfolio-test-cluster"
    error_message = "Cluster name must follow the IAM naming contract."
  }
  assert {
    condition     = one([for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "Container Insights must be enabled."
  }
  assert {
    condition     = aws_ecs_cluster_capacity_providers.this.capacity_providers == toset(["FARGATE"])
    error_message = "The cluster must use the FARGATE capacity provider only."
  }
}

# ---------------------------------------------------------------------------
# Task definition
# ---------------------------------------------------------------------------
run "task_definition_is_hardened_arm64" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this.family == "portfolio-test-app"
    error_message = "Family must be portfolio-test-app."
  }
  assert {
    condition     = aws_ecs_task_definition.this.cpu == "256" && aws_ecs_task_definition.this.memory == "512"
    error_message = "Task size must be 256 CPU / 512 MiB."
  }
  assert {
    condition     = aws_ecs_task_definition.this.runtime_platform[0].cpu_architecture == "ARM64" && aws_ecs_task_definition.this.runtime_platform[0].operating_system_family == "LINUX"
    error_message = "Task must run on LINUX/ARM64 (Graviton)."
  }
  assert {
    condition     = aws_ecs_task_definition.this.network_mode == "awsvpc" && aws_ecs_task_definition.this.requires_compatibilities == toset(["FARGATE"])
    error_message = "Task must be Fargate with awsvpc networking."
  }
  assert {
    condition     = aws_ecs_task_definition.this.execution_role_arn != aws_ecs_task_definition.this.task_role_arn
    error_message = "Task and execution roles must be separate."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].user == "101:101"
    error_message = "Container must run as 101:101."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].readonlyRootFilesystem == true
    error_message = "Root filesystem must be read-only."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].linuxParameters.capabilities.drop == ["ALL"]
    error_message = "All Linux capabilities must be dropped."
  }
  assert {
    condition     = toset([for m in jsondecode(aws_ecs_task_definition.this.container_definitions)[0].mountPoints : m.containerPath]) == toset(["/tmp", "/var/cache/nginx"])
    error_message = "Only /tmp and /var/cache/nginx may be writable."
  }
  assert {
    condition     = toset([for v in aws_ecs_task_definition.this.volume : v.name]) == toset(["tmp", "var-cache-nginx"])
    error_message = "Each writable path needs a task volume."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].portMappings[0].containerPort == 8080
    error_message = "Container must expose 8080."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.logDriver == "awslogs"
    error_message = "Logs must use the awslogs driver."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-group"] == "/ecs/portfolio-test"
    error_message = "Logs must go to the group the execution role can write to."
  }
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.options["awslogs-region"] == "ap-southeast-2"
    error_message = "awslogs-region must be the current region."
  }
  assert {
    condition     = contains(jsondecode(aws_ecs_task_definition.this.container_definitions)[0].healthCheck.command, "http://127.0.0.1:8080/healthz")
    error_message = "Container health check must probe /healthz on 8080."
  }
  assert {
    condition     = aws_cloudwatch_log_group.app.name == "/ecs/portfolio-test" && aws_cloudwatch_log_group.app.retention_in_days == 14
    error_message = "Log group name/retention are wrong."
  }
}

# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
run "service_is_private_with_rollback" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.name == "portfolio-test-app" && aws_ecs_service.this.launch_type == "FARGATE"
    error_message = "Service must be portfolio-test-app on FARGATE."
  }
  assert {
    condition     = aws_ecs_service.this.desired_count == 2
    error_message = "Initial desired count must equal min_capacity (2)."
  }
  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "Tasks must not get public IPs."
  }
  assert {
    condition     = aws_ecs_service.this.network_configuration[0].subnets == toset(var.private_subnet_ids)
    error_message = "Tasks must run in the private subnets."
  }
  assert {
    condition     = aws_ecs_service.this.deployment_circuit_breaker[0].enable && aws_ecs_service.this.deployment_circuit_breaker[0].rollback
    error_message = "Circuit breaker with rollback must be on."
  }
  assert {
    condition     = aws_ecs_service.this.deployment_minimum_healthy_percent == 100 && aws_ecs_service.this.deployment_maximum_percent == 200
    error_message = "Rolling deployment must keep 100% healthy and allow 200%."
  }
  assert {
    condition     = one(aws_ecs_service.this.load_balancer).container_name == "app" && one(aws_ecs_service.this.load_balancer).container_port == 8080
    error_message = "Service must register container app:8080 in the target group."
  }
  assert {
    condition     = aws_ecs_service.this.enable_execute_command == false
    error_message = "ECS Exec must be off."
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_alb.referenced_security_group_id == var.alb_security_group_id && aws_vpc_security_group_ingress_rule.from_alb.from_port == 8080 && aws_vpc_security_group_ingress_rule.from_alb.to_port == 8080
    error_message = "Only the ALB security group may reach 8080."
  }
  assert {
    condition     = aws_vpc_security_group_egress_rule.https.from_port == 443 && aws_vpc_security_group_egress_rule.https.to_port == 443
    error_message = "Egress must be HTTPS only."
  }
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------
run "autoscaling_2_to_5_on_cpu_and_requests" {
  command = plan

  assert {
    condition     = aws_appautoscaling_target.service.min_capacity == 2 && aws_appautoscaling_target.service.max_capacity == 5
    error_message = "Scaling range must be 2-5."
  }
  assert {
    condition     = aws_appautoscaling_target.service.resource_id == "service/portfolio-test-cluster/portfolio-test-app"
    error_message = "Scalable target must point at the service."
  }
  assert {
    condition     = aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization"
    error_message = "CPU policy must track ECSServiceAverageCPUUtilization."
  }
  assert {
    condition     = aws_appautoscaling_policy.cpu.target_tracking_scaling_policy_configuration[0].target_value == 60
    error_message = "CPU target must be 60%."
  }
  assert {
    condition     = aws_appautoscaling_policy.requests.target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ALBRequestCountPerTarget"
    error_message = "Request policy must track ALBRequestCountPerTarget."
  }
  assert {
    condition     = aws_appautoscaling_policy.requests.target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].resource_label == var.request_count_resource_label
    error_message = "Request policy must use the ALB/target group resource label."
  }
  assert {
    condition = alltrue([
      for p in [aws_appautoscaling_policy.cpu, aws_appautoscaling_policy.requests] :
      p.target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60 &&
      p.target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 300
    ])
    error_message = "Cooldowns must be 60 s out / 300 s in on both policies."
  }
}

# Apply against the mock provider: checks the outputs other modules depend on.
run "outputs_follow_naming_contract" {
  command = apply

  assert {
    condition     = output.cluster_name == "portfolio-test-cluster" && output.service_name == "portfolio-test-app"
    error_message = "Cluster/service outputs are wrong."
  }
  assert {
    condition     = output.task_definition_family == "portfolio-test-app" && output.container_name == "app"
    error_message = "Family/container outputs are wrong."
  }
  assert {
    condition     = output.log_group_name == "/ecs/portfolio-test"
    error_message = "Log group output is wrong."
  }
}

# ---------------------------------------------------------------------------
# Guard rails (inputs that must be rejected)
# ---------------------------------------------------------------------------
run "rejects_invalid_fargate_size" {
  command = plan
  variables {
    task_memory = 4096
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_shared_task_and_execution_role" {
  command = plan
  variables {
    task_role_arn = "arn:aws:iam::123456789012:role/portfolio-test-ecs-execution"
  }
  expect_failures = [aws_ecs_task_definition.this]
}

run "rejects_root_user" {
  command = plan
  variables {
    container_user = "0"
  }
  expect_failures = [var.container_user]
}

run "rejects_untagged_image" {
  command = plan
  variables {
    container_image = "123456789012.dkr.ecr.ap-southeast-2.amazonaws.com/portfolio-test-app"
  }
  expect_failures = [var.container_image]
}

run "rejects_single_subnet" {
  command = plan
  variables {
    private_subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
  }
  expect_failures = [var.private_subnet_ids]
}

run "rejects_max_below_min" {
  command = plan
  variables {
    min_capacity = 3
    max_capacity = 2
  }
  expect_failures = [aws_ecs_service.this]
}
