output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "azs" {
  description = "Availability zones in use."
  value       = module.network.azs
}

output "private_subnet_ids" {
  description = "Private subnet IDs."
  value       = module.network.private_subnet_ids
}

output "nat_public_ips" {
  description = "NAT gateway egress IPs (one per AZ)."
  value       = module.network.nat_public_ips
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

output "alb_dns_name" {
  description = "ALB DNS name: target of the proxied Cloudflare CNAME."
  value       = module.alb.alb_dns_name
}

output "origin_secret_parameter_name" {
  description = "SSM SecureString with the X-Origin-Verify value."
  value       = module.alb.origin_secret_parameter_name
}

output "ecs_cluster_name" {
  description = "ECS cluster (ECS_CLUSTER in CD)."
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "ECS service (ECS_SERVICE in CD)."
  value       = module.ecs.service_name
}

output "ecs_task_definition_family" {
  description = "Task definition family."
  value       = module.ecs.task_definition_family
}

output "ecs_container_name" {
  description = "Container the CD pipeline renders the image into."
  value       = module.ecs.container_name
}

output "alerts_topic_arn" {
  description = "SNS alerts topic (KMS CMK)."
  value       = module.observability.sns_topic_arn
}

output "alarm_names" {
  description = "CloudWatch alarm names."
  value       = module.observability.alarm_names
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = module.observability.dashboard_url
}
