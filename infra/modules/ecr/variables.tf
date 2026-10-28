variable "name" {
  description = "Repository name, for example portfolio-dev-app."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", var.name))
    error_message = "name must be a valid ECR repository name (lowercase letters, digits, . _ -)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for image encryption. null uses the AWS-managed aws/ecr key (no CMK cost)."
  type        = string
  default     = null
}

variable "force_delete" {
  description = "Allow terraform destroy to delete the repository while it still holds images. true in dev, false in prod."
  type        = bool
  default     = false
}

variable "keep_image_count" {
  description = "Number of most recent images to keep. Older images are expired so rollbacks stay possible without unbounded storage."
  type        = number
  default     = 20
  validation {
    condition     = var.keep_image_count >= 5
    error_message = "keep_image_count must be at least 5 so recent revisions stay available for rollback."
  }
}

variable "untagged_expiry_days" {
  description = "Days after which untagged images (for example leftovers from failed pushes) are expired."
  type        = number
  default     = 1
}
