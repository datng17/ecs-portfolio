output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "azs" {
  description = "Availability zones in use."
  value       = module.network.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.network.private_subnet_ids
}

output "nat_public_ips" {
  description = "NAT gateway egress IPs."
  value       = module.network.nat_public_ips
}

output "flow_log_group_name" {
  description = "VPC flow log group."
  value       = module.network.flow_log_group_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for docker push."
  value       = module.ecr.repository_url
}

output "ecs_execution_role_arn" {
  description = "ECS task execution role ARN."
  value       = module.iam.execution_role_arn
}

output "ecs_task_role_arn" {
  description = "ECS task role ARN."
  value       = module.iam.task_role_arn
}

output "github_plan_role_arn" {
  description = "Role ARN for the CI plan job (AWS_PLAN_ROLE_ARN)."
  value       = module.iam.github_plan_role_arn
}

output "github_deploy_role_arns" {
  description = "Role ARNs for the CD deploy jobs, by GitHub environment."
  value       = module.iam.github_deploy_role_arns
}
