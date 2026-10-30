# Troubleshooting Log

Each entry: **Symptom → Root cause → Fix → Prevention**.

---

## T-001: ECS MCP `ListClusters` denied by SCP

- **Symptom:** `ecs_resource_management ListClusters` returned `AccessDeniedException ... explicit deny in a
  service control policy p-qouqwmfs`.
- **Root cause:** the account `681990781993` belongs to AWS Organization `o-j3m8hgv5p4`. A region-restriction
  SCP denies most regional APIs outside `ap-southeast-2`. `.kiro/settings/mcp.json` still had
  `AWS_REGION=us-east-1` for the ECS MCP server.
- **Fix:** set `AWS_REGION=ap-southeast-2` for the ecs, cloudwatch, iac and api MCP servers. Pricing can stay
  on us-east-1, because the Pricing API endpoint isn't regional. Until then, pass the region explicitly on
  each call.
- **Prevention:** the preflight probe matrix (Task 0) runs every required read API in both regions, so region
  SCPs show up before any `terraform apply`.

## T-002: `iam:CreateOpenIDConnectProvider` / `iam:GetOpenIDConnectProvider` denied by SCP

- **Symptom:** `aws iam get-open-id-connect-provider` returned explicit deny from SCP `p-8v7l4082`.
  `simulate-principal-policy` showed `iam:CreateOpenIDConnectProvider = explicitDeny` even though the user
  has `AdministratorAccess`.
- **Root cause:** an organization guardrail stops member accounts from managing IAM identity providers. This
  is a common pattern in sandbox and training accounts.
- **Impact:** the planned GitHub Actions OIDC trust (Tasks 6, 11, 12) can't be created from this account.
- **Fix:** user decision (Task 6): the org admin creates the provider. Terraform takes its ARN from the
  `github_oidc_provider_arn` variable and has no resource or data source for it. The GitHub roles can't be
  assumed until the provider exists (see PROGRESS.md B-1).
- **Prevention:** add `iam:CreateOpenIDConnectProvider` to the preflight simulation for any CI/CD-over-OIDC
  design.

## T-003: Cost allocation tags can't be activated from a linked account

- **Symptom:** `aws ce list-cost-allocation-tags` returned "Linked account doesn't have access to cost
  allocation tags".
- **Root cause:** cost allocation tags are managed in the Organization's management (payer) account only.
- **Fix:** drop `aws_ce_cost_allocation_tag` from Terraform. The Budget is account-wide instead of
  tag-filtered. The Cost Explorer "by tag" screenshot needs the payer account to activate `Project`/`Env`.
  Otherwise use "group by Service".
- **Prevention:** check the account type (`organizations describe-organization`) early.

## T-004: Editing `.kiro/settings/mcp.json` blocked for the agent

- **Symptom:** the agent's write to `.kiro/settings/mcp.json` was denied by IDE permission scope.
- **Root cause:** Kiro protects MCP settings files from agent writes on purpose.
- **Fix:** the user edits the file by hand (exact changes listed in PROGRESS.md).
- **Prevention:** none needed. This is expected behaviour.
## T-005: gitleaks full-history scan exited with code 137
- **Symptom:** the first `gitleaks git` run over the full history recorded `exit code: 137` in
  `evidence/06-gitleaks.txt`, with no findings summary.
- **Root cause:** 137 means SIGKILL. The scan of 228 commits (~71 MB of diffs, mostly template images) takes
  about 9.5 minutes. The foreground shell call timed out first and the container was killed. Memory was not
  the cause (peak ~275 MiB of 7.7 GiB).
- **Fix:** run the container detached with `--name gitleaks-hist`, write output to `evidence/raw/`, and
  `docker wait` for it with a long timeout. The re-run finished with `no leaks found`, exit 0.
- **Prevention:** run long scans detached, or narrow the range with `--log-opts` in CI (for example only the
  pushed commits), and keep the full-history scan as a one-off.

## T-006: Local smoke test false negatives from AdGuard HTML injection

- **Symptom:** the first `scripts/smoke.ps1` run against `http://localhost:8080` reported 14/17 PASS. The
  "no inline `<script>`", body and bundle checks failed, and the HTML contained
  `<script src="//local.adguard.org/...">`. `curl.exe -i http://localhost:8080/` on the same host showed
  clean HTML.
- **Root cause:** AdGuard on the Windows host intercepts traffic from .NET `HttpClient`
  (`Invoke-WebRequest`) and injects its own script into HTML responses. The container was serving the
  correct content.
- **Fix:** `smoke.ps1` now uses `curl.exe`, which AdGuard doesn't filter. The reference run uses
  `smoke.sh` from a `curlimages/curl` container on the compose network (`http://web:8080`), so no host
  software sits in the path. Both pass 21/21.
- **Prevention:** run smoke tests from a container (or CI runner), never through a desktop HTTP stack. If a
  body check fails, compare with `curl.exe -i` before blaming the image.

## T-007: Docker Desktop engine returned 500 on `_ping`

- **Symptom:** `docker run ...` failed with `500 Internal Server Error ... dockerDesktopLinuxEngine/_ping`
  during the first containerised smoke run.
- **Root cause:** the Docker Desktop Linux engine (WSL2 VM) had stopped responding. The exact trigger
  wasn't captured. It coincided with a `-v ${PWD}/scripts:/scripts:ro` Windows-path bind mount, so that
  pattern was dropped as a precaution.
- **Fix:** the engine had recovered on the next session (`docker version` reported server 29.9.1). The
  script is now streamed through stdin instead of a bind mount:
  `cmd /c "docker run --rm -i --network portfolio_default curlimages/curl:latest sh -s -- http://web:8080 < scripts\smoke.sh"`.
  Use `cmd /c` with `<`: piping `Get-Content` in pwsh appends CRLF, so `sh` ends with `sh: \r: not found`
  and exit 127 even when every check passed.
- **Prevention:** run `docker version` before long Docker steps. If the server section is missing,
  restart Docker Desktop (or `wsl --shutdown`) rather than killing processes. Avoid bind-mounting Windows
  paths for one-off scripts.
- **Recurrence (Task 4):** the engine returned 500 again at the start of a session, with no bind mount
  involved, so the bind mount wasn't the trigger. `docker desktop restart` brought it back immediately
  (server 29.9.1). Scanner sources are still streamed in with
  `cmd /c "tar -c -C infra . | docker run --rm -i ... sh -c ""mkdir -p /w && tar -x -C /w && ..."""`.
  When building `sh -c` strings inside a pwsh command, escape `$?` as `` `$? ``, otherwise pwsh expands it
  first and prints `True`/`False` instead of the container's exit code.

## T-008: tflint AWS plugin download timed out (Task 5)

- **Symptom:** the first `tflint --init` for the network module failed with `Failed to install a plugin;
  Failed to download checksums.txt ... dial tcp 185.199.109.133:443: i/o timeout`.
- **Root cause:** a transient network timeout to `release-assets.githubusercontent.com`. The container also
  had no persistent plugin directory, so every run had to download the ruleset again.
- **Fix:** mount a named volume for the plugin cache and init once:
  `docker run --rm -v "${PWD}:/data" -v tflint-plugins:/root/.tflint.d -w /data/envs/dev ghcr.io/terraform-linters/tflint:latest --config /data/.tflint.hcl --init`.
  The retry installed `tflint-ruleset-aws` 0.50.0, and later runs reuse the volume.
- **Prevention:** keep the `tflint-plugins` volume. In CI, cache `~/.tflint.d` and set `GITHUB_TOKEN` to
  avoid rate limits.

## T-009: `terraform plan -out=dev.tfplan` fails in pwsh with "Too many command line arguments"

- **Symptom:** `terraform plan -input=false -lock-timeout=60s -out=dev.tfplan` exited 1 with
  `Error: Too many command line arguments`.
- **Root cause:** pwsh parses an unquoted `-out=dev.tfplan` as `-out=dev` plus a separate `.tfplan`
  argument, so Terraform sees an extra positional argument.
- **Fix:** quote flag arguments that contain `=` and `.`: `terraform plan '-input=false' '-out=dev.tfplan'`.
- **Prevention:** always quote `-flag=value` arguments to native tools in pwsh scripts and docs.

## T-010: `terraform providers lock` for five platforms timed out (Task 7)

- **Symptom:** after adding the `http` and `random` providers, `terraform providers lock` with five
  `-platform` flags ran past the 5-minute command timeout with no output.
- **Root cause:** without provider arguments the command re-downloads every provider for every platform. The
  AWS provider is several hundred MB per platform, and its hashes were already in the lock file.
- **Fix:** lock only the new providers:
  `terraform providers lock '-platform=windows_amd64' '-platform=windows_386' '-platform=linux_amd64' '-platform=linux_arm64' '-platform=darwin_arm64' hashicorp/http hashicorp/random`.
  It finished in seconds and the lock file now has 5 `h1:` hashes per provider.
- **Prevention:** when adding a provider, pass its address to `providers lock` instead of relocking all of them.

## T-011: checkov CKV_AWS_65 failed only when scanning from the dev env (Task 8)

- **Symptom:** `checkov -d modules/ecs` passed CKV_AWS_65 (Container Insights), but the scan of all of
  `infra/` failed it for `module.ecs.aws_ecs_cluster.this`, called from `envs/dev/main.tf`.
- **Root cause:** dev passed `container_insights = var.ecs_container_insights`. checkov doesn't resolve an
  env-level variable through a module call, so it saw an unresolved value instead of `"enabled"`.
- **Fix:** removed the env-level variable (it had no use: dev and prod both want `enabled`). The module
  default `enabled` now applies and checkov resolves it. Result: 252 passed / 0 failed.
- **Prevention:** don't expose a security-relevant setting as an env variable unless an environment
  actually needs a different value. If one does, set a literal in the module call rather than a variable.

## T-012: `terraform -chdir=infra/$d` failed with "cannot find the file specified" (Task 9)

- **Symptom:** a validate loop over several directories printed `Error handling -chdir option: chdir infra/$d`
  for every directory.
- **Root cause:** the argument was written as `'-chdir=infra/$d'`. pwsh doesn't expand variables inside
  single quotes, so Terraform received the literal text `$d`.
- **Fix:** use double quotes for arguments that contain a variable: `terraform "-chdir=infra/$d" validate`.
- **Prevention:** single quotes for literal `-flag=value` arguments (T-009), double quotes when the value
  contains a variable.

## T-013: Plan after the first apply wanted to replace the ECS task definition (Task 10)

- **Symptom:** right after `Apply complete! Resources: 109 added`, `terraform plan -detailed-exitcode` exited 2
  with `1 to add, 0 to change, 1 to destroy`: `module.ecs.aws_ecs_task_definition.this must be replaced`. The
  `container_definitions` diff removed `environment = []`, `systemControls = []`, `volumesFrom = []` and
  `linuxParameters.capabilities.add = []`.
- **Root cause:** the ECS API returns these fields as empty lists even when the request omits them. The AWS
  provider compares the stored JSON with the config and treats the difference as a change. Any change to
  `container_definitions` forces a new revision. Nothing changed in AWS.
- **Fix:** declare the four empty lists in `local.container_definitions` (`infra/modules/ecs/main.tf`). The
  next plan reported `No changes` (exit 0), and `terraform test` in `modules/ecs` still passes 11/11. The replacement
  was never applied. It would have deregistered revision 1, which the service is running.
- **Prevention:** run `terraform plan -detailed-exitcode` right after every first apply. When writing
  `container_definitions`, declare the fields ECS fills with defaults (`environment`, `mountPoints`,
  `portMappings`, `volumesFrom`, `systemControls`, `capabilities.add`) explicitly.

## T-014: Cloudflare origin header created as a Response Header Transform Rule (Task 10)

- **Symptom:** every request to `https://test.name.vn` through Cloudflare returned `403`, `text/plain`,
  body `Forbidden` (9 bytes), and the response to the visitor carried an `X-Origin-Verify` header. The ALB
  access logs show these requests as `elb_status_code 403`, target `-`, `actions_executed fixed-response`,
  matched rule `0` (the default action), from 00:41 to 01:26 UTC on 2026-10-29.
- **Root cause:** the `portfolio-origin-verify` rule was created as a **Response** Header Transform Rule. A
  response rule adds the header to Cloudflare's reply to the visitor, so the ALB never received it (default
  action 403) and the secret was published to anyone who opened the site. It happened twice: after the first
  occurrence the secret was rotated (SSM version 1 -> 2, `origin_secret_version = "2"`), and the rule for the
  version 2 value was also created response-side for a while.
- **Fix:** the user deleted the response rules and created a **Request** Header Transform Rule with the same
  name, filter and header. The ALB then matched rule 100 and forwarded (first forwarded 200 at 01:31:39 UTC).
  The live smoke test passes 22/22 and the response has no `X-Origin-Verify` (`evidence/07-smoke.txt`).
- **Status / OPEN RISK (PROGRESS.md B-4):** the current secret (SSM version 2) was publicly exposed while the
  response rule was active. The user chose to skip rotation in Task 10, and again before Task 11 (CI keeps
  `TF_DEV_ORIGIN_SECRET_VERSION = 2`). The risk remains open. Anyone who saw it can reach the
  origin only from a Cloudflare IP (the security group still drops other sources), but they could do so
  through their own Cloudflare zone. **To rotate later (before any public sharing):** set
  `origin_secret_version = "3"` in the gitignored `infra/envs/dev/terraform.tfvars`, apply, then edit the
  value of the existing Request rule right away.
- **Prevention:** `scripts/smoke.sh` and `scripts/smoke.ps1` now fail if `GET /` returns an
  `X-Origin-Verify` header (presence only, the value is never printed). `docs/CLOUDFLARE.md` step 3 has a
  warning on the rule type and how to check it with `curl -I`.

## T-015: `iam simulate-principal-policy` returned `explicitDeny` for allowed deploy actions (Task 12)

- **Symptom:** simulating `portfolio-gha-deploy-dev` for `ecr:GetAuthorizationToken`,
  `ecs:RegisterTaskDefinition` and the other `Resource "*"` actions returned `explicitDeny`, although the
  role's inline policy allows them.
- **Root cause:** the simulation includes the organization's region SCP, which denies requests outside
  ap-southeast-2. Without a request context the simulator has no `aws:RequestedRegion`, so the SCP deny
  matched. (A second attempt in the shell printed nothing: the helper function assigned to `$args`, which is
  an automatic variable in PowerShell.)
- **Fix:** pass `--context-entries ContextKeyName=aws:RequestedRegion,ContextKeyValues=ap-southeast-2,ContextKeyType=string`
  and name the argument array something other than `$args`. All 16 action/resource pairs were then `allowed`.
- **Prevention:** in this account always add the `aws:RequestedRegion` context when simulating, and never
  use `$args`/`$input` as variable names in pwsh helpers.

## T-016: OIDC assume denied after the provider existed: immutable subject claims (Task 12)

- **Symptom:** after the org-level OIDC provider was created (B-1), the re-run of CI run 40803339770
  (commit `d71672a`) failed `plan (dev)` and `plan (prod)` at `configure-aws-credentials` with
  `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`.
- **Root cause:** GitHub issues immutable subject claims for repositories created after 2026-07-15
  ([GitHub docs](https://docs.github.com/en/actions/reference/security/oidc#immutable-subject-claims),
  [changelog](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/)).
  `datng17/ecs-portfolio` was created 2026-10-27, so its tokens carry
  `repo:datng17@179402133/ecs-portfolio@1435398390:ref:refs/heads/main` (plan) and
  `...:environment:<env>` (deploy), with the owner ID and repository ID from the GitHub API. The trust
  policies used `StringEquals` on the old `repo:datng17/ecs-portfolio:...` form, so they never matched.
  The error text is the same as for any other `sub`/`aud` mismatch.
- **Fix:** the IAM module builds the subject prefix `repo:<owner>@<owner_id>/<repo>@<repo_id>` from new
  variables `github_owner_id` and `github_repository_id` (digits only, required when
  `create_github_roles = true`; dev defaults 179402133 and 1435398390). Matching stays exact
  `StringEquals`, no wildcards; the `aud` condition is unchanged. The dev plan changes only the `sub` in
  the three `gha-*` trust policies (3 in-place updates).
- **Side effect:** checkov CKV_AWS_358 then failed both trust documents. Its repo regex
  (`checkov/common/util/oidc_utils.py`, `gh_repo_regex`) expects `<owner>/<repo>` and rejects
  `<owner>@<id>/<repo>@<id>`. It's a false positive for this exact-match trust, so it's skipped inline on
  `gha_plan_assume` and `gha_deploy_assume` with that justification (checkov 335/0/47).
- **Prevention:** before writing an OIDC trust policy, check the repository's subject format: its
  creation date (`gh api repos/<owner>/<repo> --jq .created_at`, after 2026-07-15 means immutable) and the
  IDs (`--jq '.owner.id, .id'`). When in doubt, print the real claim once from a workflow (decode the
  token's payload, never log the token itself) and compare it with `aws iam get-role`.
