# Cloudflare setup (dev)

The user makes every change in this file in the Cloudflare dashboard (R9). The agent only reads the values
from Terraform and verifies the result.

Zone: `test.name.vn`. Origin: the dev ALB in ap-southeast-2. Do these steps after the full
`terraform apply` (Task 10), because the ALB DNS name and the origin secret don't exist before it.

## 0. Get the two values

```powershell
cd infra/envs/dev
terraform output -raw alb_dns_name
# Origin secret (48 chars). Don't paste it into chat, tickets or git.
aws ssm get-parameter --region ap-southeast-2 --name /portfolio-dev/alb/origin-verify-secret `
  --with-decryption --query Parameter.Value --output text
```

## 1. SSL/TLS

- **SSL/TLS → Overview:** encryption mode **Full (strict)**. The ALB serves the ACM certificate for
  `test.name.vn`, so Cloudflare can validate it.
- **SSL/TLS → Edge Certificates:** **Always Use HTTPS** on. **Minimum TLS Version** 1.2.
- Leave **HSTS** in Cloudflare off. nginx already sends `Strict-Transport-Security`.

## 2. DNS record

**DNS → Records → Add record:**

| Field | Value |
|---|---|
| Type | `CNAME` |
| Name | `@` (the apex, `test.name.vn`) |
| Target | the `alb_dns_name` output, e.g. `portfolio-dev-alb-123456789.ap-southeast-2.elb.amazonaws.com` |
| Proxy status | **Proxied** (orange cloud) |
| TTL | Auto |

Cloudflare flattens a CNAME at the apex automatically. If a record for `@` already exists (A, AAAA or
CNAME), edit it instead of adding a second one.

## 3. Transform Rule: origin header

**Rules → Transform Rules → Modify Request Header → Create rule:**

| Field | Value |
|---|---|
| Rule name | `portfolio-origin-verify` |
| If incoming requests match | Custom filter expression: `(http.host eq "test.name.vn")` |
| Then | **Set static** |
| Header name | `X-Origin-Verify` |
| Value | the secret from step 0 |

Deploy the rule. Without it, the ALB answers every request with `403 Forbidden`.

## 4. Features that break the CSP

The CSP is `default-src 'self'` with no inline scripts, so turn off anything that injects scripts:

- **Speed → Optimization → Content Optimization:** **Rocket Loader** off.
- **Scrape Shield:** **Email Address Obfuscation** off.
- **Analytics & Logs → Web Analytics:** no automatic setup (RUM injection) for this site.

## 5. Tell the agent

Reply "Cloudflare done". The agent then runs the checks below and saves them to `evidence/07-smoke.txt`.

## Verification (agent)

```powershell
# Live site through Cloudflare: 21 checks.
cmd /c "docker run --rm -i curlimages/curl:latest sh -s -- https://test.name.vn < scripts\smoke.sh"
# Direct to the ALB from a non-Cloudflare IP: the security group drops it (timeout).
curl.exe -sk --max-time 10 -o NUL -w "%{http_code}`n" https://<alb_dns_name>/
# Through Cloudflare, the response carries cf-ray and comes from the origin.
curl.exe -sI https://test.name.vn/healthz
```

The "no header → 403" rule is checked with the ALB itself: `aws elbv2 describe-rules` shows the default
action `fixed-response 403` and the header rule at priority 100.

## Rotating the secret

1. Bump `origin_secret_version` in `infra/envs/dev/terraform.tfvars` and apply. From this moment Cloudflare
   gets 403.
2. Read the new value (step 0) and update the Transform Rule value right away.

## Teardown (Task 18)

Delete the `@` CNAME record and the `portfolio-origin-verify` Transform Rule. The SSL/TLS settings can stay.
