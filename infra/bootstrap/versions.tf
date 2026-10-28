terraform {
  # >= 1.10 for S3-native state locking (use_lockfile) in the envs that use this bucket.
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Bootstrap keeps LOCAL state on purpose: it creates the bucket every other stack stores state in.
  # terraform.tfstate here is gitignored. Back it up, or re-import the resources if it is lost.
}
