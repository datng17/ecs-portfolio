# Runbook

Operational procedures for the portfolio on ECS Fargate (ap-southeast-2). Task 17 extends this file with
deploy, rollback, scaling and incident procedures.

## GitHub setup (CI, Task 11)

Workflow: `.github/workflows/ci.yml`. It runs on every push and pull request to `main`, and on manual
dispatch.

| Job | Runner | What it checks |
|---|---|---|
| `app` | ubuntu-24.04 | `npm ci`, `npm run lint`, `npm run test:ci`, `npm run build` (Node 24) |
| `container` | ubuntu-24.04-arm | hadolint, Trivy config, native arm64 build, compressed size < 50 MB, Trivy image (HIGH/CRITICAL fails), read-only compose smoke test (`scripts/smoke.sh`) |
| `iac` | ubuntu-24.04 | `terraform fmt -check`, tflint (9 dirs), checkov (all of `infra/`), `validate` (bootstrap, dev, prod), `terraform test` in `modules/ecs` |
| `secrets` | ubuntu-24.04 | gitleaks over the pushed range (`before..sha`, PR `base..head`, full history on the first push) |
| `plan (dev)`, `plan (prod)` | ubuntu-24.04 | `terraform plan` through OIDC as `portfolio-gha-plan`, output in the job summary. Needs all four jobs above. Runs only on `main` (not on PRs) and only when `AWS_PLAN_ROLE_ARN` is set |

All actions are pinned to full commit SHAs and all scanner images to digests (the same tool versions as the
local evidence). The workflow token is read-only (`contents: read`); only the plan job adds `id-token: write`.

### Checklist

1. **OIDC provider (account admin, B-1).** The SCP blocks this account from creating it. Ask the org admin to
   create an IAM OIDC identity provider in `681990781993`:
   - Provider URL `https://token.actions.githubusercontent.com`
   - Audience `sts.amazonaws.com`

   Until it exists, `sts:AssumeRoleWithWebIdentity` fails with `No OpenIDConnect provider found`, so leave
   `AWS_PLAN_ROLE_ARN` unset (step 3). The plan jobs then show as skipped and the rest of CI still runs.
2. **Actions settings** (Settings → Actions → General):
   - Allow GitHub Actions to run.
   - Workflow permissions: **Read repository contents and packages permissions**.
   - Optional: "Require actions to be pinned to a full-length commit SHA".
3. **Repository variables** (Settings → Secrets and variables → Actions → Variables). Repository-level,
   because the plan job must not use `environment:`: the `gha-plan` trust is
   `repo:datng17/ecs-portfolio:ref:refs/heads/main`, and an environment changes the OIDC `sub` claim.

   | Variable | Value | Why |
   |---|---|---|
   | `AWS_PLAN_ROLE_ARN` | `arn:aws:iam::681990781993:role/portfolio-gha-plan` | Role for the plan jobs. Set it only after step 1 |
   | `TF_DEV_IMAGE_TAG` | `98e5ce1ff2c22cbde3ebb63c8a7ddcad5d16a022` | The tag Terraform's task definition revision was created with. Without it the default `initial` makes the plan replace the task definition. Keep it at the Terraform value, not the tag CD rolls out later |
   | `TF_DEV_ORIGIN_SECRET_VERSION` | `2` (`3` after the B-4 rotation) | Must match `origin_secret_version` in the gitignored `infra/envs/dev/terraform.tfvars`, otherwise the plan regenerates the origin secret. It's a counter, not the secret |
   | `TF_PROD_IMAGE_TAG`, `TF_PROD_ORIGIN_SECRET_VERSION` | leave unset | prod is never applied; the variable defaults apply |

4. **Repository secret** (same page → Secrets):

   | Secret | Value | Why |
   |---|---|---|
   | `ALERT_EMAIL` | the address in `infra/envs/dev/terraform.tfvars` | `alert_email` is a required variable with no default. Using a different address would show the SNS subscription and budget as changed. CI masks it in logs and replaces it with `<redacted>` in the job summary |

   No AWS keys are stored. The origin secret stays in Terraform state and SSM; CI never sees it in clear text
   (the plan prints it as sensitive) and the binary plan file is never uploaded.
5. **Environments** (Settings → Environments), used by CD in Task 12. The deploy roles trust
   `repo:datng17/ecs-portfolio:environment:<env>`:
   - `dev`: deployment branches limited to `main`. Variable `AWS_DEPLOY_ROLE_ARN` =
     `arn:aws:iam::681990781993:role/portfolio-gha-deploy-dev`.
   - `prod`: deployment branches limited to `main`, required reviewer (yourself), variable
     `AWS_DEPLOY_ROLE_ARN` = `arn:aws:iam::681990781993:role/portfolio-gha-deploy-prod`. Repository variable
     `PROD_ENABLED` stays unset (prod is never deployed, R2).
6. **Branch protection** for `main` (after the first green run, so the check names exist): require the status
   checks `app (lint, test, build)`, `container (arm64)`, `iac (fmt, tflint, checkov, validate, test)`,
   `secrets (gitleaks)`. Don't require the plan checks, since they're skipped on pull requests.
7. **Push** `main` (needs explicit approval, R9): `git push -u origin main`.
8. **Verify**: Actions → CI → the run for the pushed commit. The graph shows `app`, `container`, `iac` and
   `secrets` in parallel, then `plan (dev)` and `plan (prod)`. Each plan job summary has the result line and the
   full plan. Expected: dev `No changes.`, prod `Plan: 118 to add, 0 to change, 0 to destroy.`

### CI troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Could not assume role with OIDC: No OpenIDConnect provider found` | Provider missing (B-1) | Step 1, or unset `AWS_PLAN_ROLE_ARN` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `sub` mismatch: run from a branch other than `main`, a PR, or a job with `environment:` | Plan only from `main` without an environment |
| `Repository secret ALERT_EMAIL is not set` | Step 4 missing | Add the secret |
| Dev plan replaces `module.ecs.aws_ecs_task_definition.this` | `TF_DEV_IMAGE_TAG` unset or wrong | Step 3 |
| Dev plan replaces `module.alb.random_password.origin_secret` | `TF_DEV_ORIGIN_SECRET_VERSION` doesn't match the tfvars | Step 3. Never apply such a plan from CI (it can't: the role is read-only) |
| tflint `Failed to install a plugin` | GitHub API rate limit or network | Re-run the job (the token is already passed) |
| Trivy image job fails on a new HIGH CVE | Upstream base image or Alpine package | Rebuild after the upstream fix, or bump the base digest in the Dockerfile |
