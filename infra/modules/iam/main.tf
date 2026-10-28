data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  name_prefix        = "${var.project}-${var.env}"
  app_log_group_name = coalesce(var.app_log_group_name, "/ecs/${local.name_prefix}")
  app_log_group_arn  = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.app_log_group_name}"

  # Naming contract shared with the ECS module (Task 8) and the other environment stack.
  # Deploy roles are scoped by name, so they work before the target resources exist.
  env_names = {
    for e in ["dev", "prod"] : e => {
      cluster        = "${var.project}-${e}-cluster"
      repository     = "${var.project}-${e}-${var.ecr_repository_suffix}"
      execution_role = "${var.project}-${e}-ecs-execution"
      task_role      = "${var.project}-${e}-ecs-task"
      family_prefix  = "${var.project}-${e}-"
    }
  }

  github_oidc_host  = "token.actions.githubusercontent.com"
  github_deploy_set = var.create_github_roles ? toset(var.github_deploy_environments) : toset([])
}

# ---------------------------------------------------------------------------
# ECS task execution role (used by the ECS agent: image pull + log delivery)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    # Confused-deputy protection: only ECS in this account and region.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = local.env_names[var.env].execution_role
  description        = "ECS task execution role for ${local.name_prefix}: pull from ECR, write container logs"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# Scoped replacement for AmazonECSTaskExecutionRolePolicy (which allows pull from every repo and
# writes to every log group).
data "aws_iam_policy_document" "execution" {
  # checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken has no resource-level permissions; AWS requires Resource "*".
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "PullFromOwnRepository"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid    = "WriteContainerLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    # "<group-arn>:*" matches the group and its streams (CreateLogStream authorizes on the group).
    resources = ["${local.app_log_group_arn}:*"]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "ecr-pull-and-logs"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------------------------------------------------------------------------
# ECS task role (used by the application). nginx serving static files calls no AWS APIs,
# so the role has no policies. It exists so permissions can be added without touching the
# execution role.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = local.env_names[var.env].task_role
  description        = "ECS task role for ${local.name_prefix}: intentionally empty (the app calls no AWS APIs)"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ---------------------------------------------------------------------------
# GitHub Actions trust (OIDC). The provider itself is created by the org admin (B-1).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "gha_plan_assume" {
  count = var.create_github_roles ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Exact match: only jobs without an environment on refs/heads/<branch> (no PRs, no forks, no tags).
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/${var.github_plan_branch}"]
    }
  }
}

data "aws_iam_policy_document" "gha_deploy_assume" {
  for_each = local.github_deploy_set

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Exact match: only jobs that declare `environment: <env>`, so GitHub environment protection
    # rules (reviewers, branch policy) apply before the role can be assumed.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_repository}:environment:${each.key}"]
    }
  }
}

# --- gha-plan: read-only, plus the S3 lock files ------------------------------
resource "aws_iam_role" "gha_plan" {
  count = var.create_github_roles ? 1 : 0

  name                 = "${var.project}-gha-plan"
  description          = "GitHub Actions terraform plan (${var.github_repository} ref ${var.github_plan_branch})"
  assume_role_policy   = data.aws_iam_policy_document.gha_plan_assume[0].json
  max_session_duration = 3600
}

# terraform plan refreshes every managed resource type, so it needs broad read access.
# ReadOnlyAccess grants no write actions; the inline policy below adds only the state lock files.
resource "aws_iam_role_policy_attachment" "gha_plan_readonly" {
  count = var.create_github_roles ? 1 : 0

  role       = aws_iam_role.gha_plan[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "gha_plan_state" {
  count = var.create_github_roles ? 1 : 0

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}"]
  }
  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}/envs/*/terraform.tfstate"]
  }
  # use_lockfile: plan creates and deletes <key>.tflock. It never writes the state object itself.
  statement {
    sid    = "ManageLockFiles"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["arn:${local.partition}:s3:::${var.state_bucket_name}/envs/*/terraform.tfstate.tflock"]
  }
}

resource "aws_iam_role_policy" "gha_plan_state" {
  count = var.create_github_roles ? 1 : 0

  name   = "terraform-state-read-and-lock"
  role   = aws_iam_role.gha_plan[0].id
  policy = data.aws_iam_policy_document.gha_plan_state[0].json
}

# --- gha-deploy-<env>: push image, roll the service -------------------------
resource "aws_iam_role" "gha_deploy" {
  for_each = local.github_deploy_set

  name                 = "${var.project}-gha-deploy-${each.key}"
  description          = "GitHub Actions deploy to ${var.project}-${each.key} (${var.github_repository} environment ${each.key})"
  assume_role_policy   = data.aws_iam_policy_document.gha_deploy_assume[each.key].json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "gha_deploy" {
  for_each = local.github_deploy_set

  # checkov:skip=CKV_AWS_356:ecr:GetAuthorizationToken and ecs:Register/Describe/Deregister/ListTaskDefinition(s) have no resource-level permissions; AWS requires Resource "*". Every other statement is scoped to this environment's ARNs.
  # checkov:skip=CKV_AWS_111:Same actions as above: they cannot be constrained by resource. The service update and PassRole they lead to are scoped below.
  statement {
    sid       = "EcrAuthToken"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid    = "PushToEnvRepository"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
    ]
    resources = ["arn:${local.partition}:ecr:${local.region}:${local.account_id}:repository/${local.env_names[each.key].repository}"]
  }
  statement {
    sid    = "TaskDefinitions"
    effect = "Allow"
    actions = [
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:DeregisterTaskDefinition",
      "ecs:ListTaskDefinitions",
    ]
    resources = ["*"]
  }
  # Tags copied from the previous revision are applied on register; allow tagging only then.
  statement {
    sid       = "TagTaskDefinitionsOnRegister"
    effect    = "Allow"
    actions   = ["ecs:TagResource"]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${local.env_names[each.key].family_prefix}*:*"]
    condition {
      test     = "StringEquals"
      variable = "ecs:CreateAction"
      values   = ["RegisterTaskDefinition"]
    }
  }
  statement {
    sid    = "UpdateEnvService"
    effect = "Allow"
    actions = [
      "ecs:UpdateService",
      "ecs:DescribeServices",
    ]
    resources = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${local.env_names[each.key].cluster}/*"]
  }
  # The new revision references these roles; ECS requires iam:PassRole for them.
  statement {
    sid    = "PassEnvTaskRoles"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/${local.env_names[each.key].execution_role}",
      "arn:${local.partition}:iam::${local.account_id}:role/${local.env_names[each.key].task_role}",
    ]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "gha_deploy" {
  for_each = local.github_deploy_set

  name   = "deploy-${var.project}-${each.key}"
  role   = aws_iam_role.gha_deploy[each.key].id
  policy = data.aws_iam_policy_document.gha_deploy[each.key].json
}
