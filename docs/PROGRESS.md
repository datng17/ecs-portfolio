# Progress

Spec: `.kiro/specs/ecs-portfolio/{requirements,design,tasks}.md`. 🛑 = needs explicit user approval.

## Task checklist

- [x] Task 0: Spec files, preflight and MCP setup
- [x] Task 1: Repo hygiene (origin → datng17/ecs-portfolio, branch main, gitleaks 0 leaks, committed locally, not pushed)
- [x] Task 2: Unit tests and lint (10/10 tests pass, lint 0 warnings, evidence in `evidence/01-unit-test.txt`)
- [x] Task 3: Container (ARM64) (hadolint 0, Trivy 0 vulns / 0 misconfig, 27.9 MB compressed, smoke 21/21, committed locally)
- [x] Task 4: Terraform bootstrap (state) (applied 2026-10-28, 7 resources, tflint 0, checkov 27/0/3 skipped, no drift)
- [x] Task 5: Network module + dev env wiring (plan 26 to add / 0 change / 0 destroy, fmt + validate OK, tflint 0, checkov module 62 passed / 0 failed / 5 skipped with inline justification, not applied)
- [x] Task 6: ECR + IAM modules (plan 38 to add / 0 change / 0 destroy, fmt + validate OK, tflint 0, checkov ecr 3/0/0, iam 61/0/3, dev 164/0/8, not applied; OIDC provider ARN is a variable per B-1)
- [x] Task 7: ALB module (plan 84 to add / 0 change / 0 destroy, fmt + validate OK, tflint 0, checkov alb 53/0/8, infra minus bootstrap 217/0/16, not applied)
- [x] Task 8: ECS module (terraform test 11/11 pass, plan 98 to add / 0 change / 0 destroy, fmt + validate OK, tflint 0, checkov ecs 35/0/4, infra minus bootstrap 252/0/20, Dockerfile gains `VOLUME`, not applied)
- [x] Task 9: Observability module + prod env (dev plan 111 / 0 / 0, prod plan 118 / 0 / 0, fmt + validate OK, tflint 0 on all 9 dirs, checkov all of `infra/` 337/0/43, observability 30/0/3, evidence in `evidence/04-iac-scan.txt`, not applied)
- [x] Task 10: First dev deploy (109 added, no drift after T-013 fix, Cloudflare done by the user, live smoke 22/22 via `https://test.name.vn`, direct ALB access times out, no header → ALB 403, 2 tasks HEALTHY in 2 AZs, evidence in `evidence/07-smoke.txt`; open risk B-4)
- [x] Task 11: CI pipeline (pushed `d71672a`, run 40803339770 green: app, container, iac, secrets pass; plan skipped until B-1 is resolved)
- [ ] Task 12: CD pipeline (workflows written, actionlint 0, deploy-role permissions simulated OK, committed locally; live test pending push approval and B-1)
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

## Unit tests and lint (Task 2)

| Item | Result |
|---|---|
| `npm run lint` | `eslint src --ext .ts,.tsx --max-warnings=0`, exit 0 |
| `npm run test:ci` | `react-scripts test --coverage --watchAll=false`, 10/10 pass, exit 0 |
| Tests (`src/App.test.tsx`) | owner name and role, 4 section headings, 4 nav buttons scroll to the right `#id`, dark/light theme toggle |
| Mocks (`src/setupTests.ts`) | `IntersectionObserver`, `matchMedia`, `window.scrollTo`, `Element.scrollIntoView` (jsdom lacks them) |
| Coverage | 65.97% statements, 54.54% branches. `App.tsx` 100%. No threshold enforced yet |
| Known noise | One `ReactDOMTestUtils.act` deprecation warning (React 18.3 with `@testing-library/react` 13). CRA's babel-preset warning about `@babel/plugin-proposal-private-property-in-object`. Neither fails the run |

## Container (Task 3)

| Item | Result |
|---|---|
| Build | `docker buildx build --platform linux/arm64 -t portfolio:local --load .`. Builder on `$BUILDPLATFORM` (node:24-alpine), runtime `nginxinc/nginx-unprivileged:alpine`, both pinned by digest |
| Runtime hardening | USER 101, port 8080, exec-form HEALTHCHECK (busybox wget `/healthz`), curl removed, `apk upgrade` for Alpine fixes |
| nginx | `/healthz`, gzip, `no-cache` HTML / `immutable` static, security headers via include, SPA fallback, dotfiles 404, `server_tokens off`, JSON access logs, real_ip (VPC + Cloudflare ranges) |
| Compose run | healthy; `ReadonlyRootfs=true`, `User=101:101`, `CapDrop=[ALL]`, `no-new-privileges`, tmpfs `/tmp` + `/var/cache/nginx`, bound to 127.0.0.1:8080. Writes to `/etc` fail with "Read-only file system" |
| hadolint | 2.15.1, 0 findings, exit 0 (`evidence/02-hadolint.txt`) |
| Trivy vuln | 0.76.1, 0 vulnerabilities (all severities), HIGH/CRITICAL gate exit 0 (`evidence/03-trivy.txt`) |
| Trivy vuln, before fix | 3 HIGH (brotli-libs, curl, libcurl), 3 MEDIUM, 44 LOW, 2 UNKNOWN, all fixable. Pinned base digest was already the latest upstream |
| Trivy misconfig | Dockerfile, 0 findings, exit 0 |
| Size, uncompressed | 65.9 MB (`docker image inspect`). Base alone ~60.7 MB, so < 50 MB uncompressed isn't reachable with the mandated base |
| Size, compressed | 27.9 MB (gzip of `docker save`, approximates ECR). Base 25.0 MB, app 2.5 MB, patch layer 2.7 MB. **< 50 MB target met on this metric** |
| Smoke, container | `smoke.sh` in `curlimages/curl` on `portfolio_default` → `http://web:8080`: 21/21 PASS, exit 0 |
| Smoke, host | `smoke.ps1` (curl.exe) → `http://localhost:8080`: 21/21 PASS, exit 0. Earlier 3 failures were AdGuard injection (T-006) |
| Raw output | `evidence/raw/smoke-local-*.txt`, `evidence/raw/trivy-*` (gitignored). `evidence/07-smoke.txt` is left for Task 10 |
| Known noise | `nginx -t` via `docker exec` under QEMU logs `io_setup() failed (38: Function not implemented)`. QEMU user-mode lacks Linux AIO; the test still succeeds and native Graviton isn't affected |

## Terraform bootstrap (Task 4)

| Item | Result |
|---|---|
| Stack | `infra/bootstrap`, local state (gitignored). Terraform 1.16.3, AWS provider 6.70.0. Lock file has windows/linux (amd64, arm64)/darwin_arm64 hashes |
| Bucket | `tfstate-681990781993-apse2` in ap-southeast-2. `allowed_account_ids` pins the account |
| Settings | Versioning Enabled. SSE-KMS with AWS-managed `aws/s3` key + Bucket Key (no CMK cost). All 4 public-access-block flags on. `BucketOwnerEnforced`. `prevent_destroy` |
| Bucket policy | Deny `aws:SecureTransport=false`, deny `s3:TlsVersion < 1.2`. Policy status `IsPublic=false` |
| Lifecycle | Non-current versions expire after 90 days (newest 10 kept). Abort incomplete multipart uploads after 7 days. Remove expired delete markers (left by `.tflock` objects) |
| Env backends | `infra/envs/{dev,prod}/backend.tf`: S3, key `envs/<env>/terraform.tfstate`, `encrypt = true`, `use_lockfile = true`. `terraform init` in dev succeeds |
| fmt / validate | exit 0 / valid |
| tflint | 0.65.0 + AWS ruleset 0.50.0 (`infra/.tflint.hcl`), 0 findings, exit 0 |
| checkov | 3.3.30, 27 passed, 0 failed, 3 skipped with in-code reasons (CKV_AWS_18 access logging, CKV_AWS_144 cross-region replication, CKV2_AWS_62 event notifications), exit 0 |
| Apply | 7 added, 0 changed, 0 destroyed. Follow-up plan: no changes |
| Demo (CLI) | `get-bucket-versioning` Enabled, `get-bucket-encryption` aws:kms + BucketKeyEnabled, `get-public-access-block` all true, ownership BucketOwnerEnforced |
| TLS-only test | `list-objects-v2` over `http://s3.ap-southeast-2.amazonaws.com` → AccessDenied, "explicit deny in a resource-based policy" |
| Raw output | `evidence/raw/{tflint,checkov}-bootstrap.txt`, `bootstrap-apply.txt`, `bootstrap-verify.txt` (gitignored) |
| Teardown note | Removing the bucket (Task 18) needs `prevent_destroy` removed and the bucket emptied of all versions first |

## ECR + IAM modules (Task 6)

| Item | Result |
|---|---|
| ECR (`infra/modules/ecr`) | Repo `portfolio-dev-app`. `IMMUTABLE` tags, scan on push, `encryption_type = KMS` with the AWS-managed `aws/ecr` key (`kms_key_arn` variable for a CMK), `force_delete` from `ecr_force_delete` (true in dev). Lifecycle: untagged expire after 1 day, keep the 20 newest images |
| Execution role | `portfolio-dev-ecs-execution`. Trust `ecs-tasks.amazonaws.com` with `aws:SourceAccount` + `aws:SourceArn` (ECS in this account/region). Inline policy replaces `AmazonECSTaskExecutionRolePolicy`: pull only from the env repo, logs only to `/ecs/portfolio-dev` |
| Task role | `portfolio-dev-ecs-task`, same trust, no policies (nginx calls no AWS APIs) |
| gha-plan | `portfolio-gha-plan`. `StringEquals` aud `sts.amazonaws.com`, sub `repo:datng17/ecs-portfolio:ref:refs/heads/main`. `ReadOnlyAccess` + inline: read state, write/delete only `envs/*/terraform.tfstate.tflock` |
| gha-deploy-dev / -prod | `portfolio-gha-deploy-{dev,prod}`. sub `repo:datng17/ecs-portfolio:environment:{dev,prod}`. Push to `portfolio-<env>-app`, register/describe/deregister task definitions, `UpdateService`/`DescribeServices` on `service/portfolio-<env>-cluster/*`, `iam:PassRole` on the env's execution + task role only, with `iam:PassedToService = ecs-tasks.amazonaws.com` |
| Ownership | GitHub roles are account-level, so only the dev stack creates them (`create_github_roles = true`); the prod stack (Task 9) passes `false` and creates only its ECS roles |
| Naming contract for Task 8 | Cluster `portfolio-<env>-cluster`, log group `/ecs/portfolio-<env>`, task definition family prefix `portfolio-<env>-` (module outputs `ecs_cluster_name`, `app_log_group_name`, `task_definition_family_prefix`) |
| OIDC provider | Not created, not read (B-1). ARN from `github_oidc_provider_arn`, default `arn:aws:iam::681990781993:oidc-provider/token.actions.githubusercontent.com` |
| fmt / validate | exit 0 / valid |
| tflint | envs/dev, modules/ecr, modules/iam: 0 findings, exit 0 |
| checkov | ecr 3 passed / 0 failed. iam 61 / 0 / 3 skipped: CKV_AWS_356 on the execution policy and CKV_AWS_356 + CKV_AWS_111 on the deploy policy, because `ecr:GetAuthorizationToken` and the `ecs:*TaskDefinition*` actions have no resource-level permissions. dev (all modules) 164 / 0 / 8 |
| Plan | 38 to add (26 network + 2 ECR + 10 IAM), 0 change, 0 destroy. Not applied |
| Raw output | `evidence/raw/plan-dev-ecr-iam.txt`, `plan-dev-trust-policies.txt`, `checkov-ecr-iam.txt` (gitignored) |
| Open risk | IAM may reject `CreateRole` if the Federated principal (the OIDC provider) doesn't exist yet. If the Task 10 apply fails on the `gha-*` roles, apply with `create_github_roles = false` until the admin creates the provider |

## ALB module (Task 7)

| Item | Result |
|---|---|
| Module | `infra/modules/alb`, wired into `infra/envs/dev` as `module.alb`. New providers `hashicorp/http` 3.6.3 and `hashicorp/random` 3.9.1; lock file has hashes for windows_amd64/386, linux_amd64/arm64, darwin_arm64 |
| Security group | `portfolio-dev-alb-sg`. Ingress 80 and 443 from each Cloudflare IPv4 range only (15 ranges, 30 rules), fetched from `https://www.cloudflare.com/ips-v4` by the `http` data source. Preconditions: HTTP 200, list not empty, every entry is a CIDR, at most 60 rules. Egress only tcp/8080 to the VPC CIDR. No IPv6 (the ALB is IPv4-only, so Cloudflare connects over IPv4) |
| Certificate | `aws_acm_certificate` data source by domain `test.name.vn` (all statuses looked up). HTTPS listener precondition `status == "ISSUED"`. Plan resolves to `arn:aws:acm:ap-southeast-2:681990781993:certificate/15eda235-...` (matches R1) |
| TLS policy | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06`: TLS 1.3 plus TLS 1.2 with AEAD ciphers only. Validation rejects any non-`TLS13` policy. TLS 1.3-only (`TLS13-1-3`) was not chosen so Cloudflare's origin connection works on either version |
| Listeners | `:80` 301 redirect to `:443`. `:443` default action fixed-response **403** `Forbidden`. Rule priority 100: header `X-Origin-Verify` equals the secret → forward to the target group |
| Origin secret | `random_password` (48 chars, alphanumeric, because ALB header matching treats `*` and `?` as wildcards) stored in SSM SecureString `/portfolio-dev/alb/origin-verify-secret` (AWS-managed `aws/ssm` key). The plan shows the rule condition as sensitive. Rotate by bumping `origin_secret_version`, then update the Cloudflare Transform Rule. The value is in Terraform state, which is SSE-KMS encrypted and private |
| Target group | `portfolio-dev-tg`, `target_type = ip`, HTTP:8080, health check `/healthz` matcher 200, interval 15 s, 2 healthy / 3 unhealthy, deregistration delay 30 s |
| ALB | `portfolio-dev-alb`, public subnets, `drop_invalid_header_fields = true`, desync mitigation `defensive`, HTTP/2, deletion protection from `alb_deletion_protection` (false in dev) |
| Access logs | Bucket `portfolio-dev-alb-logs-681990781993-ap-southeast-2`, prefix `alb`. SSE-S3 (the only encryption ALB log delivery supports), BucketOwnerEnforced, public access blocked, versioning, logs expire after 14 days, TLS-only deny. Policy uses the `logdelivery.elasticloadbalancing.amazonaws.com` principal with the account ID in the path, the form AWS now recommends over the legacy Sydney ELB account `783225319266`. `force_destroy` true in dev |
| Outputs for Task 8/9 | `security_group_id`, `target_group_arn`, `https_listener_arn` (the ECS service depends on it), `alb_arn_suffix`, `target_group_arn_suffix`, `alb_request_count_resource_label` |
| fmt / validate | exit 0 / valid |
| tflint | envs/dev and modules/alb: 0 findings, exit 0 |
| checkov | alb 53 passed / 0 failed / 8 skipped, each with an inline reason: CKV2_AWS_28 (WAF: Cloudflare WAF at the edge plus the Cloudflare-only security group; AWS WAF ~$10+/month), CKV_AWS_150 (deletion protection is variable-driven), CKV_AWS_378 (HTTP to targets in private subnets; TLS ends at the ALB), CKV_AWS_337 (aws/ssm key, no CMK), CKV_AWS_145 (ALB logs support SSE-S3 only), CKV_AWS_18, CKV_AWS_144, CKV2_AWS_62. All of `infra/` except bootstrap: 217 / 0 / 16 |
| Plan | 84 to add (38 earlier + 46 ALB), 0 change, 0 destroy. Not applied |
| Raw output | `evidence/raw/plan-dev-alb.txt`, `checkov-alb.txt` (gitignored) |
| Check in Task 11 | `gha-plan` refreshes the SecureString parameter. `ReadOnlyAccess` covers `ssm:GetParameter` and the `aws/ssm` key policy allows decrypt through SSM for account principals, so no extra IAM is expected; confirm on the first CI plan |

## ECS module (Task 8)

| Item | Result |
|---|---|
| Module | `infra/modules/ecs`, wired into `infra/envs/dev` as `module.ecs`. Cluster name, log group and family come from the IAM module outputs, so the deploy and execution role scopes always match |
| Cluster | `portfolio-dev-cluster`, Container Insights `enabled` (module variable also accepts `enhanced`/`disabled`), capacity provider FARGATE only |
| Logs | `/ecs/portfolio-dev`, retention from `log_retention_days` (14 in dev), encrypted with a new CMK `alias/portfolio-dev-ecs-logs` (rotation on, logs service limited to this group by encryption context; ~$1/month) |
| Task definition | Family `portfolio-dev-app`, FARGATE/awsvpc, 256 CPU / 512 MiB, LINUX/ARM64, separate execution and task roles (precondition). Container `app`: user `101:101`, `readonlyRootFilesystem`, all capabilities dropped, `initProcessEnabled`, port 8080, health check `wget http://127.0.0.1:8080/healthz` (30 s / 5 s / 3 retries / 10 s start), awslogs `non-blocking` with a 25 MB buffer, stop timeout 30 s |
| Writable paths | Task-local volumes `tmp` → `/tmp` and `var-cache-nginx` → `/var/cache/nginx`. Fargate has no tmpfs, and a bind mount is root-owned 0755 unless the image declares the path as `VOLUME`, so the Dockerfile now has `VOLUME ["/tmp", "/var/cache/nginx"]` ([AWS bind mount docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/bind-mounts.html)) |
| Image check | hadolint 0, arm64 build OK. `docker run --read-only --user 101:101 --cap-drop ALL` with the anonymous volumes (same copy-from-image behaviour): `/tmp` 1777, `/var/cache/nginx` owned by nginx, `nginx.pid` written, writes to `/etc` fail, `/healthz` 200, container healthy. Compose (tmpfs) smoke still PASS |
| Service | `portfolio-dev-app`, FARGATE `LATEST`, private subnets, no public IP, SG `portfolio-dev-ecs-sg` (in: 8080 from the ALB SG only; out: 443 only). Desired 2, min healthy 100 %, max 200 %, grace period 30 s, circuit breaker with rollback, AZ rebalancing, ECS managed tags, ECS Exec off. `ignore_changes = [task_definition, desired_count]` |
| Load balancer ordering | The HTTPS default action is a fixed 403, so the target group is only attached through the origin-verified rule. The service waits on both the listener and that rule (`terraform_data.load_balancer_ready`), because ECS rejects a target group that nothing forwards to |
| Autoscaling | Scalable target 2–5. Target tracking `ECSServiceAverageCPUUtilization` 60 % and `ALBRequestCountPerTarget` 1000 req/target/min (`ecs_request_count_target`, tune in Task 14), both with scale-out cooldown 60 s and scale-in 300 s |
| `terraform test` | `infra/modules/ecs/tests/ecs.tftest.hcl`, mocked AWS provider (no credentials). 11 runs: cluster, task hardening, service, autoscaling, outputs (mock apply), plus 6 rejection cases (invalid Fargate size, shared roles, root user, untagged image, single subnet, max < min). 11 passed / 0 failed. Mutation check: changing the CPU target to 70 and the user to 1000 fails the 2 matching runs |
| fmt / validate | exit 0 / valid (module and dev) |
| tflint | modules/ecs and envs/dev: 0 findings, exit 0 |
| checkov | ecs 35 passed / 0 failed / 4 skipped (the 3 key-policy `Resource "*"` checks and CKV_AWS_338 retention, same reasons as the network module). All of `infra/` except bootstrap: 252 / 0 / 20 (see T-011) |
| Plan | 98 to add (84 earlier + 14 ECS), 0 change, 0 destroy. Not applied |
| Raw output | `evidence/raw/terraform-test-ecs.txt`, `plan-dev-ecs.txt`, `checkov-ecs.txt`, `checkov-infra-task8.txt`, `build-task8.txt` (gitignored) |
| Task 10 notes | `image_tag` defaults to `initial`, which doesn't exist in ECR. Push `:<sha>` first and apply with `image_tag = "<sha>"`, or the tasks fail to pull and the circuit breaker trips. Terraform owns only the first revision: later `image_tag` changes register a revision the service ignores, so roll out through CD. Trivy wasn't re-run, since only image metadata (`VOLUME`) changed; CI rescans it in Task 11 |

## Observability module + prod env (Task 9)

| Item | Result |
|---|---|
| Module | `infra/modules/observability`, wired into both envs as `module.observability`. Dimensions come from the ALB (`alb_arn_suffix`, `target_group_arn_suffix`) and ECS (`cluster_name`, `service_name`) outputs |
| KMS | CMK `alias/portfolio-<env>-alerts`, rotation on, 7-day deletion window. Key policy: root admin, plus `kms:GenerateDataKey*` / `kms:Decrypt` for `cloudwatch.amazonaws.com` and `budgets.amazonaws.com` (the SNS docs' form for AWS event sources) |
| SNS | Topic `portfolio-<env>-alerts`, SSE with the CMK. Topic policy: account owner, CloudWatch alarms (`aws:SourceAccount` + `aws:SourceArn` `arn:aws:cloudwatch:ap-southeast-2:<acct>:alarm:*`), Budgets (`aws:SourceArn` `arn:aws:budgets::<acct>:*`), deny publish without TLS. Email subscription to `alert_email` (pending until confirmed) |
| Alarms | All 1-minute periods, 3 of 5 datapoints, `treat_missing_data = notBreaching`, `alarm_actions` and `ok_actions` = the topic. `alb-elb-5xx` (Sum >= 5), `alb-target-5xx-rate` (metric math `IF(requests >= 20, 100 * FILL(errors,0) / requests, 0)` > 1 %), `tg-unhealthy-hosts` (Maximum >= 1), `alb-latency-p95` (p95 TargetResponseTime > 0.3 s, the SLO), `ecs-cpu-high` (> 80 %, above the 60 % scaling target), `ecs-memory-high` (> 80 %) |
| Dashboard | `portfolio-<env>`: alarm status, requests, ELB/target 5xx and ELB 4xx, target 5xx rate with the 0.1 % SLO line, p50/p95/p99 latency with the 300 ms line, healthy/unhealthy hosts, CPU/memory with the 60 % and 80 % lines, running vs desired tasks (Container Insights) with min/max lines |
| Budget | `portfolio-account-monthly-cost`, COST, 30.00 USD monthly, ACTUAL > 50/80/100 % and FORECASTED > 100 %, each to the SNS topic and directly to `alert_email` (works before the SNS subscription is confirmed). Account-wide per B-3, so only the dev stack creates it (`create_budget = true`); prod passes `false` |
| Cost allocation tags | Not in Terraform (B-3, T-003: linked account). `default_tags` still put Project/Env/Owner/CostCenter/ManagedBy on every resource, ready for the payer account to activate |
| `alert_email` | Required variable with an email-format validation, set only in the gitignored `terraform.tfvars`. Both tfvars hold the placeholder `alerts@example.com`; a `check` block warns on every plan until it's replaced. **Set a real address before the Task 10 apply** |
| prod env | `infra/envs/prod`: same modules; `10.20.0.0/16`, 3 AZs, NAT per AZ (3), ECR/Logs interface endpoints on, log retention 90 days, ECR `force_delete = false`, ALB deletion protection on, ALB-log bucket `force_destroy = false`. `create_github_roles = false` (dev owns the gha-* roles) and no budget. Same ACM certificate (`test.name.vn`), since only one exists; a real prod would get its own hostname and cert. Validate and plan only (R2) |
| fmt / validate | exit 0 / valid (bootstrap, dev, prod, observability) |
| tflint | 0.65.0 + AWS ruleset 0.50.0: bootstrap, envs/dev, envs/prod and all 6 modules, 0 findings each |
| checkov | 3.3.30. All of `infra/` (bootstrap + both envs + modules): 337 passed / 0 failed / 43 skipped (26 unique skips; modules are counted once per env that calls them). observability alone: 30 / 0 / 3 (the same 3 key-policy `Resource "*"` skips as the network and ECS CMKs) |
| Plans | dev: 111 to add (98 earlier + 13 observability), 0 change, 0 destroy. prod: 118 to add, 0 change, 0 destroy (no gha-* roles, no budget). Not applied |
| Raw output | `evidence/raw/plan-dev-task9.txt`, `plan-prod-task9.txt`, `tflint-task9.txt`, `checkov-infra-task9*.txt`, `checkov-observability.txt` (gitignored) |
| Task 10 notes | Confirm the SNS email after apply, otherwise alarms reach no one (budget emails still arrive directly). Alarms on ALB/ECS metrics start in `INSUFFICIENT_DATA` and move to `OK` once traffic and tasks report |

## First dev deploy (Task 10)

| Item | Result |
|---|---|
| Image | `portfolio-dev-app:98e5ce1ff2c22cbde3ebb63c8a7ddcad5d16a022` (arm64), pushed after the ECR-only apply (2 resources). ECR basic scan 0 findings |
| Apply | 2026-10-28, `terraform apply '-input=false' '-lock-timeout=60s' -no-color dev.tfplan`: **109 added, 0 changed, 0 destroyed**, exit 0. ALB 2m38s, NAT 1m48s. Record in `evidence/05-terraform.txt` (redacted) |
| B-1 fallback | Not needed. IAM accepted `CreateRole` for `portfolio-gha-plan` / `portfolio-gha-deploy-{dev,prod}` without the OIDC provider. The roles still can't be assumed until the admin creates it |
| Drift check | First plan: replace the task definition (provider normalisation of empty lists, T-013). Not applied. Fixed in `modules/ecs`, then `plan -detailed-exitcode` exit 0, `No changes`. `terraform test` 11/11 |
| ALB | `portfolio-dev-alb-1560386417.ap-southeast-2.elb.amazonaws.com`. `:443` default fixed-response 403, rule 100 `http-header X-Origin-Verify` (1 value) → forward to `portfolio-dev-tg`. `:80` redirect 301 |
| ECS service | `portfolio-dev-app`: desired 2, running 2, 1 PRIMARY deployment, rollout `COMPLETED`, steady state 16:34 |
| Tasks | 2 RUNNING, HEALTHY, arm64, revision 1: one in ap-southeast-2a, one in ap-southeast-2b |
| Target health | 2/2 healthy (10.10.135.204, 10.10.158.45, port 8080) |
| Direct to ALB | `curl.exe` from this machine (not Cloudflare) to `https://` and `http://<alb_dns_name>/`: `000`, curl exit 28 (10 s timeout). The security group drops it |
| SNS | Email subscription on `portfolio-dev-alerts` is **confirmed** (it has a real subscription ARN) |
| Alarms | All 6 `portfolio-dev-*` alarms `OK` |
| Secret hygiene | The alert email and the origin secret don't appear in `evidence/05-terraform.txt` or the raw apply/plan/check files (checked by string match) |
| Raw output | `evidence/raw/apply-dev-task10.txt`, `plan-dev-postapply-task10.txt`, `plan-dev-postapply2-task10.txt`, `postapply-checks-task10.txt` (gitignored) |
| Cloudflare | Done by the user: `@` CNAME → ALB (proxied), Full (strict), Request Header Transform Rule `portfolio-origin-verify`. The rule was first created response-side twice, which leaked the secret; the secret was rotated once (SSM version 1 → 2). See T-014 and B-4 |
| Smoke (live) | 2026-10-29 01:36 UTC, `smoke.sh` in `curlimages/curl` → `https://test.name.vn`: **22/22 PASS**, exit 0. `smoke.ps1` from the host: 22/22. No check needed an edge-aware change (Cloudflare passes Cache-Control, gzip and the security headers through; `Server: cloudflare`) |
| New smoke check | `GET / has no X-Origin-Verify header` in `smoke.sh` and `smoke.ps1` (presence only). Local read-only compose container: 22/22 PASS |
| Through Cloudflare | `/` and `/healthz` → 200 with `CF-RAY`, `cf-cache-status: DYNAMIC`, 0 `X-Origin-Verify` headers |
| Direct to ALB (re-check) | 2026-10-29 01:38 UTC: `https://` and `http://<alb_dns_name>/` → `000`, curl exit 28. Security group drops non-Cloudflare sources |
| No header → 403 | Listener: default fixed-response 403 `text/plain` `Forbidden`; rule 100 `http-header X-Origin-Verify` (1 value) → forward. ALB access logs: 9 requests 00:41–01:26 UTC with `elb_status 403`, target `-`, `fixed-response`, rule 0 (before the Request rule existed); from 01:31:39 UTC forwarded by rule 100 with 200 |
| Tasks / targets (re-check) | `537c84b2…` ap-southeast-2b and `e6e2eb56…` ap-southeast-2a, both RUNNING / HEALTHY, revision 1. Targets 10.10.135.204 (2a) and 10.10.158.45 (2b) healthy |
| Evidence | `evidence/07-smoke.txt` (redacted; secret and alert email checked absent by in-process match). Raw: `evidence/raw/smoke-live-task10.txt`, `smoke-live-ps1-task10.txt`, `smoke-local-task10.txt` (gitignored) |

## CI pipeline (Task 11)

| Item | Result |
|---|---|
| Workflow | `.github/workflows/ci.yml`: `app`, `container` (ubuntu-24.04-arm), `iac`, `secrets` in parallel, then `plan (dev)` / `plan (prod)`. Triggers: push and PR to `main`, manual dispatch |
| Pinning | actions/checkout v7.0.1, actions/setup-node v7.1.0, hashicorp/setup-terraform v4.0.1, aws-actions/configure-aws-credentials v6.3.0, each by full SHA (resolved with `git ls-remote`, peeled tags). Scanner images by digest, same versions as the local evidence: hadolint 2.15.1, Trivy 0.76.1, tflint 0.65.0, checkov 3.3.30, gitleaks 8.30.1. Terraform 1.16.3 |
| Permissions | Workflow `contents: read`; `id-token: write` only on the plan job. `persist-credentials: false` on every checkout |
| Plan inputs | No tfvars in CI. Secret `ALERT_EMAIL`; repo variables `AWS_PLAN_ROLE_ARN`, `TF_DEV_IMAGE_TAG`, `TF_DEV_ORIGIN_SECRET_VERSION` (unset values fall back to the variable defaults). The email is redacted from the job summary; the binary plan is never uploaded |
| Plan gating | Runs only on `main`, not on PRs, and only when `AWS_PLAN_ROLE_ARN` is set, so CI stays green (plan skipped) until the OIDC provider exists (B-1). Role ARN and trust confirmed with `aws iam get-role`: sub `repo:datng17/ecs-portfolio:ref:refs/heads/main`, aud `sts.amazonaws.com` |
| actionlint | 1.7.12 (Docker, with shellcheck): 0 findings |
| Local dry run of the CI commands | checkov (CI digest, read-only mount): 337 passed / 0 failed / 43 skipped. tflint (CI digest) on all 9 dirs: exit 0. gitleaks (CI digest, `--log-opts=77536ad..HEAD`, read-only mount with `safe.directory` via env): 13 commits, no leaks |
| GitHub setup checklist | `docs/RUNBOOK.md`, "GitHub setup" |
| Push | `d71672a` pushed to `origin/main` on 2026-10-29 01:55 UTC (`git push -u origin main`, reflog "update by push") |
| First CI run | [Run 40803339770](https://github.com/datng17/ecs-portfolio/actions/runs/40803339770), event `push`, conclusion **success**. `app` 51 s, `container (arm64)` 70 s, `iac` 65 s, `secrets (gitleaks)` 6 min 35 s (full history, first push), all success, 0 annotations |
| Plan jobs | Skipped as designed: `AWS_PLAN_ROLE_ARN` is unset because the OIDC provider doesn't exist yet (B-1). A skipped matrix job is shown unexpanded as `plan (${{ matrix.env }})`, since GitHub evaluates the job `if` before expanding the matrix |
| Still to verify | The plan jobs and their job summaries (expected dev `No changes.`, prod 118 to add), once the admin creates the OIDC provider and `AWS_PLAN_ROLE_ARN` and `ALERT_EMAIL` are set (RUNBOOK checklist steps 1, 3, 4) |
| Origin secret | Not rotated (user decision, B-4). `TF_DEV_ORIGIN_SECRET_VERSION` stays `2` |

## CD pipeline (Task 12)

| Item | Result |
|---|---|
| Workflows | `.github/workflows/cd.yml` (`workflow_run` of CI, completed, branch `main`) calls the reusable `.github/workflows/deploy-ecs.yml` for `dev`, then `prod` (`needs: dev`, `if: vars.PROD_ENABLED == 'true'`, prod environment reviewer) |
| Gates | `vars.CD_ENABLED == 'true'`, CI conclusion `success`, CI event `push`, head branch `main`, head repository = this repository. `CD_ENABLED` stays unset until B-1, so CD shows as skipped instead of failing on OIDC |
| Deploy job | `ubuntu-24.04-arm`, `environment: <env>` (sub `repo:datng17/ecs-portfolio:environment:<env>`), role from the environment variable `AWS_DEPLOY_ROLE_ARN`. Steps: preflight → OIDC → ECR login → build arm64 `:<sha>` (skipped if the immutable tag exists) → Trivy HIGH/CRITICAL gate → push → describe the service's current revision with tags → render → deploy + wait for stability → verify PRIMARY is the new revision and `COMPLETED` → `scripts/smoke.sh https://test.name.vn` → on failure roll back to the previous revision and deregister the new one → job summary |
| Pinning | New: aws-actions/amazon-ecr-login v2.1.7 `03f1aad`, amazon-ecs-render-task-definition v1.9.1 `8d79160`, amazon-ecs-deploy-task-definition v2.6.4 `a00d4d5` (full SHAs in the file, peeled tags from `git ls-remote`). Reused from CI: checkout v7.0.1, configure-aws-credentials v6.3.0, Trivy 0.76.1 digest |
| Permissions / concurrency | Workflow `contents: read`; deploy job `contents: read` + `id-token: write`. Group `deploy-<env>`, `cancel-in-progress: false` |
| actionlint | 1.7.12 (Docker, with shellcheck) over all workflows: 0 findings |
| IAM check | `iam simulate-principal-policy` on `portfolio-gha-deploy-dev` (region context ap-southeast-2): all 16 action/resource pairs the workflow uses are `allowed`, including `ecs:TagResource` with `ecs:CreateAction = RegisterTaskDefinition` and `iam:PassRole` with `iam:PassedToService = ecs-tasks.amazonaws.com`. `UpdateService` on the prod service: `implicitDeny` (as intended). **No IAM gaps**; no Terraform change. Raw: `evidence/raw/iam-sim-cd-task12.txt` (gitignored) |
| Read-only dry run | The workflow's CLI queries against dev: service `ACTIVE`, revision `portfolio-dev-app:1`; PRIMARY `COMPLETED` 2/2; the render input (task definition + tags) has family, 256/512, ARM64, image `:98e5ce1…`, tags Project/Owner/ManagedBy/CostCenter/Env/Name |
| Live test | **Pending.** Needs (1) the OIDC provider (B-1), (2) the `dev` environment with `AWS_DEPLOY_ROLE_ARN` and repository variable `CD_ENABLED = true`, (3) a push approved by the user (R9). Procedure: `docs/RUNBOOK.md`, "CD pipeline", "Live verification" |

## Skills note

The devops-iac skill links to `reference/`, `scripts/` and `examples/` folders that don't exist; only its
8-step workflow is usable. The ecs-task and gitignore skills are header-only stubs. The work follows AWS and
Terraform best practice instead.

## Open blockers / decisions

### B-1: GitHub OIDC provider is blocked by SCP (decided: option 1; affects Tasks 6, 11, 12)

SCP `p-8v7l4082` denies creating or reading IAM OIDC providers.

**Decision (user, Task 6):** option 1. Terraform neither creates nor reads the provider (no resource, no data
source). The IAM module takes its ARN from `github_oidc_provider_arn`, defaulted in dev (`variables.tf` and
`terraform.tfvars.example`) to `arn:aws:iam::681990781993:oidc-provider/token.actions.githubusercontent.com`.
The org admin creates the provider later (URL `https://token.actions.githubusercontent.com`, audience
`sts.amazonaws.com`). **Until then, `portfolio-gha-plan` and `portfolio-gha-deploy-{dev,prod}` can't be
assumed**, so CI plan (Task 11) and CD (Task 12) can't authenticate to AWS.

Options considered:

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

### B-4: Origin secret version 2 was publicly exposed (open risk, rotation deferred by the user)

During Task 10 the Cloudflare rule was created as a Response Header Transform Rule, so `X-Origin-Verify`
was sent to visitors (T-014). The current secret (SSM `/portfolio-dev/alb/origin-verify-secret`, version 2)
was exposed while that rule was active. The security group still limits the ALB to Cloudflare IPs, but
someone with the value could reach the origin through their own Cloudflare zone and bypass this zone's
settings. **The user chose to skip rotation in Task 10, and again before Task 11** (no apply, SSM stays at
version 2, CI uses `TF_DEV_ORIGIN_SECRET_VERSION = 2`). **The risk remains open.** To rotate later (before any
public sharing): set `origin_secret_version = "3"` in `infra/envs/dev/terraform.tfvars`, apply, then update the Request rule
value (`docs/CLOUDFLARE.md`, "Rotating the secret").

### B-3: Cost allocation tags need the payer account (affects Task 9)

Decision: drop `aws_ce_cost_allocation_tag` from Terraform and make the $30 Budget account-wide instead of
tag-filtered. The Cost Explorer "by tag" screenshot needs the payer account to activate `Project`/`Env`;
otherwise group by Service.
