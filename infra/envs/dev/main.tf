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

module "ecs" {
  source = "../../modules/ecs"

  name_prefix = local.name_prefix

  # Names come from the IAM module, so the deploy and execution role scopes always match.
  cluster_name       = module.iam.ecs_cluster_name
  log_group_name     = module.iam.app_log_group_name
  task_family        = "${module.iam.task_definition_family_prefix}app"
  execution_role_arn = module.iam.execution_role_arn
  task_role_arn      = module.iam.task_role_arn

  # First revision only. CD registers later revisions; the service ignores task_definition changes.
  container_image    = "${module.ecr.repository_url}:${var.image_tag}"
  log_retention_days = var.log_retention_days

  vpc_id                     = module.network.vpc_id
  private_subnet_ids         = module.network.private_subnet_ids
  alb_security_group_id      = module.alb.security_group_id
  target_group_arn           = module.alb.target_group_arn
  load_balancer_dependencies = [module.alb.https_listener_arn, module.alb.origin_verified_rule_arn]

  min_capacity                 = var.ecs_min_capacity
  max_capacity                 = var.ecs_max_capacity
  cpu_target_percent           = var.ecs_cpu_target_percent
  request_count_resource_label = module.alb.alb_request_count_resource_label
  request_count_target         = var.ecs_request_count_target
}
