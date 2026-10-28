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

output "alb_dns_name" {
  description = "ALB DNS name: target of the proxied Cloudflare CNAME."
  value       = module.alb.alb_dns_name
}

output "alb_security_group_id" {
  description = "ALB security group (Cloudflare IPv4 only)."
  value       = module.alb.security_group_id
}

output "alb_target_group_arn" {
  description = "Target group for the ECS service."
  value       = module.alb.target_group_arn
}

output "alb_certificate_arn" {
  description = "ACM certificate on the HTTPS listener."
  value       = module.alb.certificate_arn
}

output "origin_verify_header_name" {
  description = "Header the Cloudflare Transform Rule must add."
  value       = module.alb.origin_verify_header_name
}

output "origin_secret_parameter_name" {
  description = "SSM SecureString with the header value (aws ssm get-parameter --with-decryption)."
  value       = module.alb.origin_secret_parameter_name
}

output "alb_access_logs_bucket" {
  description = "S3 bucket with ALB access logs."
  value       = module.alb.access_logs_bucket
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
  description = "Task definition family (CD downloads the latest revision of it)."
  value       = module.ecs.task_definition_family
}

output "ecs_container_name" {
  description = "Container the CD pipeline renders the image into."
  value       = module.ecs.container_name
}

output "app_log_group_name" {
  description = "Container log group."
  value       = module.ecs.log_group_name
}
