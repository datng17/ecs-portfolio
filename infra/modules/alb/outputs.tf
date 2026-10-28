output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (app/<name>/<id>), the LoadBalancer dimension for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "alb_dns_name" {
  description = "ALB DNS name. Cloudflare's proxied CNAME points here."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "ALB hosted zone ID."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "ALB security group. The ECS service security group allows the target port from this group only."
  value       = aws_security_group.alb.id
}

output "target_group_arn" {
  description = "Target group the ECS service registers into."
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix, the TargetGroup dimension for CloudWatch metrics."
  value       = aws_lb_target_group.app.arn_suffix
}

output "alb_request_count_resource_label" {
  description = "resource_label for the ALBRequestCountPerTarget scaling metric."
  value       = "${aws_lb.this.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
}

output "https_listener_arn" {
  description = "HTTPS listener ARN. The ECS service must depend on it (a target group needs a listener before a service can use it)."
  value       = aws_lb_listener.https.arn
}

output "origin_verified_rule_arn" {
  description = "Listener rule ARN that forwards requests with the origin header."
  value       = aws_lb_listener_rule.origin_verified.arn
}

output "certificate_arn" {
  description = "ACM certificate ARN used by the HTTPS listener."
  value       = data.aws_acm_certificate.this.arn
}

output "cloudflare_ipv4_cidrs" {
  description = "Cloudflare IPv4 ranges allowed by the ALB security group."
  value       = local.cloudflare_ipv4_cidrs
}

output "origin_verify_header_name" {
  description = "Header the Cloudflare Transform Rule must set."
  value       = var.origin_verify_header_name
}

output "origin_secret_parameter_name" {
  description = "SSM SecureString holding the header value. Read with: aws ssm get-parameter --with-decryption --name <this>."
  value       = aws_ssm_parameter.origin_secret.name
}

output "access_logs_bucket" {
  description = "S3 bucket receiving ALB access logs."
  value       = aws_s3_bucket.access_logs.id
}
