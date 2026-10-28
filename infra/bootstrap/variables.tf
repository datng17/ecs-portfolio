variable "account_id" {
  description = "AWS account that owns the state bucket. The provider refuses any other account."
  type        = string
  default     = "681990781993"

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "region" {
  description = "Region for the state bucket."
  type        = string
  default     = "ap-southeast-2"
}

variable "region_short" {
  description = "Short region code used in the bucket name."
  type        = string
  default     = "apse2"
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep non-current state versions before they expire."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_retention_days >= 30
    error_message = "Keep non-current state versions for at least 30 days."
  }
}

variable "noncurrent_versions_to_keep" {
  description = "Newest non-current versions kept regardless of age."
  type        = number
  default     = 10
}
