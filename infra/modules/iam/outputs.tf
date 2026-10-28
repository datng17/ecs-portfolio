output "execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN (no policies)."
  value       = aws_iam_role.task.arn
}

output "ecs_cluster_name" {
  description = "Cluster name the deploy role is scoped to. The ECS module must use it."
  value       = local.env_names[var.env].cluster
}

output "app_log_group_name" {
  description = "Log group the execution role may write to. The ECS module must create it with this name."
  value       = local.app_log_group_name
}

output "task_definition_family_prefix" {
  description = "Task definition families must start with this prefix to be taggable by the deploy role."
  value       = local.env_names[var.env].family_prefix
}

output "github_plan_role_arn" {
  description = "gha-plan role ARN, or null when create_github_roles is false."
  value       = try(aws_iam_role.gha_plan[0].arn, null)
}

output "github_deploy_role_arns" {
  description = "Map of environment to gha-deploy-<env> role ARN."
  value       = { for e, r in aws_iam_role.gha_deploy : e => r.arn }
}
