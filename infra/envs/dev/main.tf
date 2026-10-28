locals {
  name_prefix = "${var.project}-${var.env}"
}

module "network" {
  source = "../../modules/network"

  name_prefix                = local.name_prefix
  vpc_cidr                   = var.vpc_cidr
  az_count                   = var.az_count
  single_nat_gateway         = var.single_nat_gateway
  enable_interface_endpoints = var.enable_interface_endpoints
  flow_log_retention_days    = var.log_retention_days
}

module "ecr" {
  source = "../../modules/ecr"

  name         = "${local.name_prefix}-app"
  force_delete = var.ecr_force_delete
}

module "iam" {
  source = "../../modules/iam"

  project            = var.project
  env                = var.env
  ecr_repository_arn = module.ecr.repository_arn

  # dev is the stack that owns the account-level GitHub roles (gha-plan, gha-deploy-dev, gha-deploy-prod).
  # The prod stack calls this module with create_github_roles = false.
  create_github_roles        = true
  github_oidc_provider_arn   = var.github_oidc_provider_arn
  github_repository          = var.github_repository
  github_deploy_environments = ["dev", "prod"]
}

module "alb" {
  source = "../../modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = module.network.vpc_id
  vpc_cidr          = module.network.vpc_cidr
  public_subnet_ids = module.network.public_subnet_ids

  certificate_domain    = var.certificate_domain
  origin_secret_version = var.origin_secret_version

  enable_deletion_protection = var.alb_deletion_protection
  access_logs_retention_days = var.log_retention_days
  access_logs_force_destroy  = var.alb_logs_force_destroy
}
