terraform {
  required_version = ">= 1.10"

  backend "s3" {
    bucket       = "tfstate-681990781993-apse2"
    key          = "envs/prod/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true # S3-native locking (<key>.tflock); no DynamoDB table.
  }
}
