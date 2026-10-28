provider "aws" {
  region = var.region
  # Refuse to run against any other account.
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = {
      Project    = var.project
      Env        = var.env
      Owner      = "datng17"
      CostCenter = "portfolio"
      ManagedBy  = "Terraform"
    }
  }
}
