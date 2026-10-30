variable "project" {
  description = "Project name, for example portfolio. Resource names follow <project>-<env>-<resource>."
  type        = string
}

variable "env" {
  description = "Environment that owns the ECS execution and task roles created by this module call."
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "ecr_repository_arn" {
  description = "ARN of this environment's ECR repository. The execution role may pull only from it."
  type        = string
}

variable "app_log_group_name" {
  description = "CloudWatch log group the containers write to. null means /ecs/<project>-<env> (created by the ECS module)."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# GitHub Actions (OIDC)
# ---------------------------------------------------------------------------
variable "create_github_roles" {
  description = "Create the account-level GitHub Actions roles (gha-plan and one gha-deploy-<env> per entry in github_deploy_environments). Enable in exactly one environment stack to avoid name clashes."
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "ARN of the existing IAM OIDC provider for token.actions.githubusercontent.com. Not created or read here: the SCP denies iam:CreateOpenIDConnectProvider and iam:GetOpenIDConnectProvider (blocker B-1), so the org admin creates it."
  type        = string
  default     = null
  validation {
    condition     = !var.create_github_roles || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.github_oidc_provider_arn))
    error_message = "github_oidc_provider_arn must be the ARN of the token.actions.githubusercontent.com OIDC provider when create_github_roles is true."
  }
}

variable "github_repository" {
  description = "GitHub repository (owner/name) trusted by the OIDC roles."
  type        = string
  default     = "datng17/ecs-portfolio"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

# Repositories created after 2026-07-15 get immutable OIDC subject claims:
# repo:<owner>@<owner_id>/<repo>@<repo_id>:... The numeric IDs come from the GitHub API
# (GET /repos/<owner>/<repo>: .owner.id and .id).
variable "github_owner_id" {
  description = "Numeric GitHub ID of the repository owner, used in the immutable OIDC sub claim (repo:<owner>@<owner_id>/<repo>@<repo_id>:...)."
  type        = string
  default     = null
  validation {
    condition     = !var.create_github_roles || can(regex("^[0-9]+$", var.github_owner_id))
    error_message = "github_owner_id must be the owner's numeric GitHub ID (digits only) when create_github_roles is true."
  }
}

variable "github_repository_id" {
  description = "Numeric GitHub ID of the repository, used in the immutable OIDC sub claim (repo:<owner>@<owner_id>/<repo>@<repo_id>:...)."
  type        = string
  default     = null
  validation {
    condition     = !var.create_github_roles || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be the repository's numeric GitHub ID (digits only) when create_github_roles is true."
  }
}

variable "github_plan_branch" {
  description = "Branch whose workflow runs (jobs without an environment) may assume the gha-plan role."
  type        = string
  default     = "main"
}

variable "github_deploy_environments" {
  description = "GitHub environments that get a gha-deploy-<env> role. Each role may deploy only the <project>-<env> resources."
  type        = list(string)
  default     = ["dev", "prod"]
  validation {
    condition     = alltrue([for e in var.github_deploy_environments : contains(["dev", "prod"], e)])
    error_message = "github_deploy_environments may only contain dev and prod."
  }
}

variable "ecr_repository_suffix" {
  description = "Repository name suffix: the repository for env X is <project>-X-<suffix>. Must match the ECR module call."
  type        = string
  default     = "app"
}

variable "state_bucket_name" {
  description = "Terraform state bucket. gha-plan may read state and write only the S3 lock files."
  type        = string
  default     = "tfstate-681990781993-apse2"
}
