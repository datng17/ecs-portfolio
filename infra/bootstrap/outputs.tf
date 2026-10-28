output "state_bucket_name" {
  description = "Name of the Terraform state bucket. Use it as `bucket` in the envs' S3 backend."
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "ARN of the Terraform state bucket, for IAM policies (e.g. the gha-plan role)."
  value       = aws_s3_bucket.state.arn
}

output "state_bucket_region" {
  description = "Region of the state bucket."
  value       = var.region
}
