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
- **Fix:** pending a user decision (see PROGRESS.md "Open blockers").
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
