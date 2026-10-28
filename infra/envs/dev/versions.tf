terraform {
  # required_version and the S3 backend live in backend.tf.
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
