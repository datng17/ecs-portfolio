output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_arn" {
  description = "Repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "repository_url" {
  description = "Repository URL (<account>.dkr.ecr.<region>.amazonaws.com/<name>), used for docker push and the task definition image."
  value       = aws_ecr_repository.this.repository_url
}
