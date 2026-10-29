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
   - Repository variable `CD_ENABLED` = `true` turns CD on. Set it only after step 1 and the `dev`
     environment exist; until then the CD jobs show as skipped (see "CD pipeline" below).
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

## CD pipeline (Task 12)

Workflows: `.github/workflows/cd.yml` (trigger and gates) and `.github/workflows/deploy-ecs.yml` (reusable
deploy job, one call per environment).

```
CI (push to main) --success--> CD: dev --> CD: prod (only if PROD_ENABLED, then a required reviewer)
```

`cd.yml` runs on `workflow_run` of CI (`completed`, branch `main`). The `dev` job starts only when all of these
hold: `vars.CD_ENABLED == 'true'`, the CI conclusion is `success`, the CI event was `push` (not a PR), the head
branch is `main`, and the head repository is this repository. It deploys `workflow_run.head_sha`, the commit
CI tested.

Steps in `deploy (<env>)` (runner `ubuntu-24.04-arm`, `environment: <env>`, OIDC sub
`repo:datng17/ecs-portfolio:environment:<env>`, role from the environment variable `AWS_DEPLOY_ROLE_ARN`):

| Step | What it does |
|---|---|
| Preflight | Fails if `AWS_DEPLOY_ROLE_ARN` is unset or the SHA isn't 40 hex characters |
| OIDC + ECR login | `configure-aws-credentials` v6.3.0, `amazon-ecr-login` v2.1.7 |
| Image | `portfolio-<env>-app:<sha>`. If the tag is already in ECR (re-run; tags are immutable) the build is skipped. Otherwise native arm64 build (`--provenance=false --sbom=false`, single manifest), Trivy HIGH/CRITICAL gate (same digest as CI), push |
| Current task definition | The revision the service runs now (`describe-services`), with its tags (`--include TAGS`), so CD revisions keep the Terraform `default_tags`. Not the newest revision in the family, which may be a failed one |
| Render | `amazon-ecs-render-task-definition` v1.9.1: only the `app` image changes |
| Deploy | `amazon-ecs-deploy-task-definition` v2.6.4: register, `UpdateService`, wait for stability (10 min max, 15 s polling) |
| Verify rollout | The PRIMARY deployment must be the new revision, `rolloutState` `COMPLETED`, running = desired. Needed because the stability wait also succeeds after a circuit-breaker rollback |
| Smoke test | `sh scripts/smoke.sh https://test.name.vn` (22 checks, through Cloudflare) |
| Roll back | On failure of deploy, verify or smoke: `update-service` to the previous revision, `wait services-stable`, check the PRIMARY deployment, deregister the failed revision. The job still ends red |
| Job summary | Commit, image, previous and new revision, step outcomes, rollback outcome |

Concurrency group `deploy-<env>` with `cancel-in-progress: false`: a second push waits for the running
rollout instead of cancelling it halfway. All actions are pinned to full commit SHAs. Workflow token
`contents: read`; the deploy job adds `id-token: write`.

### Variables

| Where | Name | Value |
|---|---|---|
| Repository variable | `CD_ENABLED` | `true` once the OIDC provider exists (B-1) and the `dev` environment is set up. Unset = CD skipped |
| Repository variable | `PROD_ENABLED` | leave unset (R2). Even when `true`, the prod environment's required reviewer must approve |
| Environment `dev` variable | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::681990781993:role/portfolio-gha-deploy-dev` |
| Environment `prod` variable | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::681990781993:role/portfolio-gha-deploy-prod` |

No secrets are needed: the task definition holds no secret values (the origin secret is ALB-side only).

### IAM coverage (checked with `iam simulate-principal-policy`, Task 12)

`portfolio-gha-deploy-dev` allows every call the workflow makes: `ecr:GetAuthorizationToken`,
`ecr:DescribeImages` and the push actions on `portfolio-dev-app`, `ecs:Describe/Register/DeregisterTaskDefinition`,
`ecs:TagResource` on `task-definition/portfolio-dev-*` only with `ecs:CreateAction = RegisterTaskDefinition`,
`ecs:DescribeServices`/`UpdateService` on `service/portfolio-dev-cluster/*`, and `iam:PassRole` on the dev
execution and task roles with `iam:PassedToService = ecs-tasks.amazonaws.com`. `UpdateService` on the prod
service is denied, as intended. `ecs:ListTagsForResource` isn't granted and isn't needed. If
`describe-task-definition --include TAGS` is ever refused, the step falls back to no tags and logs a warning.

### Live verification (after B-1)

1. Set `CD_ENABLED = true`, the `dev` environment and its `AWS_DEPLOY_ROLE_ARN`.
2. Commit a visible content change (for example a project description in `src/components/Project.tsx`; not
   the `Dat Nguyen` heading or the `DevOps` subtitle, which the unit tests and `smoke.sh` check) and push to
   `main` (needs approval, R9).
3. Actions: CI run → CD run (`dev` → `deploy (dev)`; `prod` skipped). The deploy job summary shows the new
   revision (`portfolio-dev-app:2` for the first CD deploy).
4. `https://test.name.vn` shows the change. Target: live within about 5 minutes of the CD job starting.
5. `aws ecs describe-services --cluster portfolio-dev-cluster --services portfolio-dev-app --region ap-southeast-2 --query 'services[0].taskDefinition'` returns the new revision.

### CD troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| CD run shows `dev` skipped | `CD_ENABLED` unset, CI not green, or CI ran for a PR | Expected until B-1; otherwise fix CI |
| `Environment variable AWS_DEPLOY_ROLE_ARN is not set` | Variable set on the repository instead of the `dev` environment | Move it to the environment |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The `sub` doesn't match `environment:dev` (job without `environment:`), or the OIDC provider is missing | Check the environment name; B-1 |
| `tag invalid: The image tag ... already exists` | Should not happen: the existing-tag check skips the push | Check the `Image tag` step output |
| `Verify rollout` fails with "circuit breaker rolled back?" | New tasks failed health checks; ECS rolled back on its own | Read ECS service events and `/ecs/portfolio-dev` logs. The rollback step re-pins the previous revision and deregisters the new one |
| Smoke test fails with 403 or a Cloudflare challenge page | Cloudflare security settings (Bot Fight Mode, WAF) challenge GitHub runner IPs | Allow the `portfolio-smoke/1.0` user agent with a WAF skip rule, or relax Bot Fight Mode |
| Terraform plan shows the task definition as changed after CD | Shouldn't: the service has `ignore_changes = [task_definition]`, and the Terraform-owned revision stays registered | Keep `TF_DEV_IMAGE_TAG` at the Terraform value |
