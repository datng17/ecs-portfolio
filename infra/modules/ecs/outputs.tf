output "cluster_name" {
  description = "ECS cluster name (ClusterName dimension for CloudWatch metrics)."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "service_name" {
  description = "ECS service name (ServiceName dimension for CloudWatch metrics)."
  value       = aws_ecs_service.this.name
}

output "service_arn" {
  description = "ECS service ARN."
  value       = aws_ecs_service.this.id
}

output "task_definition_family" {
  description = "Task definition family the CD pipeline registers revisions into."
  value       = aws_ecs_task_definition.this.family
}

output "task_definition_arn" {
  description = "ARN of the revision Terraform registered (the service may run a newer one from CD)."
  value       = aws_ecs_task_definition.this.arn
}

output "container_name" {
  description = "Container name the CD pipeline renders the image into."
  value       = var.container_name
}

output "log_group_name" {
  description = "Container log group."
  value       = aws_cloudwatch_log_group.app.name
}

output "logs_kms_key_arn" {
  description = "KMS key encrypting the container log group."
  value       = aws_kms_key.logs.arn
}

output "security_group_id" {
  description = "Service security group."
  value       = aws_security_group.service.id
}

output "autoscaling_policy_names" {
  description = "Target tracking policy names."
  value = {
    cpu      = aws_appautoscaling_policy.cpu.name
    requests = aws_appautoscaling_policy.requests.name
  }
}
