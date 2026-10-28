output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability zones in use."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB, NAT), one per AZ."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (ECS tasks), one per AZ."
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "Private route table IDs, one per AZ."
  value       = aws_route_table.private[*].id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways (egress addresses)."
  value       = aws_eip.nat[*].public_ip
}

output "endpoints_security_group_id" {
  description = "Security group on the interface endpoints, or null when they are disabled."
  value       = try(aws_security_group.endpoints[0].id, null)
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC flow logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "flow_logs_kms_key_arn" {
  description = "KMS key encrypting the flow log group."
  value       = aws_kms_key.flow_logs.arn
}
