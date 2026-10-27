# Progress

Spec: `.kiro/specs/ecs-portfolio/{requirements,design,tasks}.md`. 🛑 = needs explicit user approval.

## Task checklist

- [x] Task 0: Spec files, preflight and MCP setup
- [x] Task 1: Repo hygiene (origin → datng17/ecs-portfolio, branch main, gitleaks 0 leaks, committed locally, not pushed)
- [ ] Task 2: Unit tests and lint
- [ ] Task 3: Container (ARM64)
- [ ] Task 4: Terraform bootstrap (state) 🛑 apply
- [ ] Task 5: Network module + dev env wiring
- [ ] Task 6: ECR + IAM modules (blocked by B-1 for the OIDC provider)
- [ ] Task 7: ALB module
- [ ] Task 8: ECS module (task definition + service + autoscaling)
- [ ] Task 9: Observability module + prod env (see B-3)
- [ ] Task 10: First dev deploy 🛑 apply; Cloudflare steps done by the user
- [ ] Task 11: CI pipeline 🛑 GitHub push (blocked by B-1)
- [ ] Task 12: CD pipeline (blocked by B-1)
- [ ] Task 13: Load test and SLOs
- [ ] Task 14: Autoscaling verification
- [ ] Task 15: Rollback drill
- [ ] Task 16: Security headers and Lighthouse
- [ ] Task 17: Documentation
- [ ] Task 18: Teardown 🛑 destroy

## Preflight results (Task 0)

| Check | Result |
|---|---|
| AWS CLI | 2.38.6 |
| STS identity | account `681990781993`, `arn:aws:iam::681990781993:user/test` (AdministratorAccess) |
| Terraform | v1.16.3 (>= 1.10 required for S3 `use_lockfile`). Binary is `windows_386` |
| Docker | 29.9.1. buildx supports `linux/arm64` |
| Node / npm | v24.22.1 / 11.19.1 |
| git | 2.53 |
| uv | 0.13.1, already installed at `C:\Users\HELLO\.local\bin` (no install needed) |
| `awslabs.aws-documentation-mcp-server` | 1.2.3 |
| `awslabs.aws-api-mcp-server` | 1.6.0. Deprecated upstream; migrate to the AWS MCP Server later |
| `awslabs.aws-iac-mcp-server` | 1.0.26 |
| `awslabs.ecs-mcp-server` | 0.1.37. Needs `fastmcp>=3.2.0` (no upper bound). Existing pin `fastmcp==3.4.11` is valid and kept (latest is 4.1.4) |
| `awslabs.cloudwatch-mcp-server` | 0.3.1 |
| `awslabs.aws-pricing-mcp-server` | 1.1.1 |
| CloudWatch MCP | `describe_log_groups` in ap-southeast-2 OK (0 log groups) |
| AWS API MCP | OK. ACM cert `test.name.vn` ISSUED, SAN `test.name.vn` only, RSA-2048, expires 2027-05-13, RenewalEligibility INELIGIBLE (not attached to any resource yet) |
| ECS MCP | Fails with the configured `AWS_REGION=us-east-1` (SCP deny, T-001). Equivalent CLI call `aws ecs list-clusters --region ap-southeast-2` succeeds (`clusterArns: []`). Fixed once B-2 is applied |
| Scanner images pre-pulled | hadolint, trivy, tflint, checkov, gitleaks, k6, `node:20-alpine`, `nginxinc/nginx-unprivileged:alpine` |
| AWS Organization | Account is a member of `o-j3m8hgv5p4` (linked account) |
| Region SCP | Regional APIs allowed only in ap-southeast-2. In us-east-1, ecs/ecr/ec2/elbv2/ssm/sns are denied; cloudwatch/logs/kms/budgets are allowed |
| IAM OIDC | `iam:CreateOpenIDConnectProvider` and `iam:GetOpenIDConnectProvider` explicitly denied by SCP `p-8v7l4082` (T-002) |
| IAM roles | `iam:CreateRole`, `iam:PassRole`, `iam:PutRolePolicy` allowed |
| Other create actions (ap-southeast-2) | All required actions allowed (`simulate-principal-policy`) |
| Cost allocation tags | Denied: "linked account" (T-003) |
| Cost Explorer `GetCostAndUsage` | Works |

## Skills note

The devops-iac skill links to `reference/`, `scripts/` and `examples/` folders that don't exist; only its
8-step workflow is usable. The ecs-task and gitignore skills are header-only stubs. The work follows AWS and
Terraform best practice instead.

## Open blockers / decisions

### B-1: GitHub OIDC provider is blocked by SCP (decision needed, affects Tasks 6, 11, 12)

SCP `p-8v7l4082` denies creating or reading IAM OIDC providers. Options:

1. **Recommended:** ask the org admin to create `token.actions.githubusercontent.com` (audience
   `sts.amazonaws.com`) in account 681990781993. Terraform then takes its ARN from a variable instead of
   creating it. A data source won't work, because `iam:GetOpenIDConnectProvider` is also denied. The gha-plan
   and gha-deploy roles can still be created, since `iam:CreateRole` is allowed.
2. Ask the admin to exempt this account (or a specific role) from the SCP, so Terraform can manage the
   provider itself.
3. Fallback, **not recommended:** an IAM user with access keys stored in GitHub secrets. This violates the
   no-long-lived-keys requirement (R7).

### B-2: User must hand-edit `.kiro/settings/mcp.json` (T-004)

The agent can't write this file. Changes:

- `aws-iac` and `cloudwatch` servers: set `AWS_PROFILE` to `"default"` (replace the placeholders).
- `ecs`, `cloudwatch`, `aws-iac` and `aws-api` servers: set `AWS_REGION` to `"ap-southeast-2"`.
- `aws-pricing`: keep `us-east-1` (the Pricing API endpoint isn't regional).

Until then, MCP calls must pass the region explicitly, or use the AWS CLI with `--region ap-southeast-2`.

### B-3: Cost allocation tags need the payer account (affects Task 9)

Decision: drop `aws_ce_cost_allocation_tag` from Terraform and make the $30 Budget account-wide instead of
tag-filtered. The Cost Explorer "by tag" screenshot needs the payer account to activate `Project`/`Env`;
otherwise group by Service.
