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
