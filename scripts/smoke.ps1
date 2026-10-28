#Requires -Version 5.1
<#
.SYNOPSIS
  Smoke test for the portfolio container (local or deployed).

.DESCRIPTION
  Checks health, the HTML shell, security headers, cache headers, gzip, the
  SPA fallback and static 404s. Exits 1 if any check fails.

.EXAMPLE
  ./scripts/smoke.ps1
  ./scripts/smoke.ps1 -BaseUrl https://test.name.vn
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = $(if ($env:SMOKE_BASE_URL) { $env:SMOKE_BASE_URL } else { 'http://localhost:8080' }),
    [string]$ExpectText = 'Dat Nguyen',
    [int]$TimeoutSec = 10,
    [int]$Retries = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$BaseUrl = $BaseUrl.TrimEnd('/')

# Uses curl.exe (bundled with Windows 10+) rather than .NET HttpClient:
# host filtering software such as AdGuard intercepts PowerShell/.NET traffic
# and injects <script> tags into HTML, which breaks the body checks
# (docs/TROUBLESHOOTING.md T-006). curl does not decompress unless asked
# (--compressed) and does not follow redirects, so Content-Encoding and
# redirect status codes can be asserted directly.
$curl = (Get-Command curl.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("smoke-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

$script:failures = 0

function Invoke-Get {
    param([string]$Path, [switch]$Gzip)
    $hFile = Join-Path $tmpDir 'h'
    $bFile = Join-Path $tmpDir 'b'
    Remove-Item $hFile, $bFile -ErrorAction SilentlyContinue
    $curlArgs = @('-sS', '--max-time', "$TimeoutSec", '-A', 'portfolio-smoke/1.0',
        '-D', $hFile, '-o', $bFile, '-w', '%{http_code}')
    if ($Gzip) { $curlArgs += @('-H', 'Accept-Encoding: gzip') }
    $code = & $curl @curlArgs "$BaseUrl$Path" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $code -or $code -eq '000') { throw "request to $Path failed (curl exit $LASTEXITCODE)" }
    $headers = @{}
    foreach ($line in (Get-Content -LiteralPath $hFile)) {
        if ($line -match '^([^:\s]+):\s*(.*)$') { $headers[$Matches[1].ToLowerInvariant()] = $Matches[2].Trim() }
    }
    $body = if (Test-Path $bFile) { [System.IO.File]::ReadAllText($bFile) } else { '' }
    [pscustomobject]@{ Status = [int]$code; Headers = $headers; Body = $body }
}

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "PASS  $Name"
    } else {
        Write-Host "FAIL  $Name $Detail" -ForegroundColor Red
        $script:failures++
    }
}

function Get-Header($resp, [string]$name) {
    if ($resp.Headers.ContainsKey($name)) { $resp.Headers[$name] } else { '' }
}

Write-Host "Smoke test against $BaseUrl"

# 1. Health (retry while the container starts).
$health = $null
for ($i = 1; $i -le $Retries; $i++) {
    try { $health = Invoke-Get '/healthz'; if ($health.Status -eq 200) { break } } catch { $health = $null }
    Start-Sleep -Seconds 2
}
Assert-That 'GET /healthz -> 200 "ok"' ($null -ne $health -and $health.Status -eq 200 -and $health.Body.Trim() -eq 'ok') `
    "(status=$(if ($health) { $health.Status } else { 'no response' }))"
if ($null -eq $health) { Write-Host 'Service unreachable, aborting.' -ForegroundColor Red; exit 1 }

# 2. HTML shell.
$root = Invoke-Get '/'
Assert-That 'GET / -> 200' ($root.Status -eq 200) "(status=$($root.Status))"
Assert-That 'GET / is text/html' ((Get-Header $root 'content-type') -like 'text/html*')
Assert-That "GET / contains '$ExpectText'" ($root.Body -like "*$ExpectText*")
Assert-That 'GET / Cache-Control: no-cache' ((Get-Header $root 'cache-control') -eq 'no-cache') "(got '$(Get-Header $root 'cache-control')')"
Assert-That 'Server header hides nginx version' ((Get-Header $root 'server') -notmatch '\d') "(got '$(Get-Header $root 'server')')"
Assert-That 'No inline <script> blocks (CSP script-src self)' ($root.Body -notmatch '<script>[^<]')

# 3. Security headers.
$required = @{
    'content-security-policy'   = "default-src 'self'"
    'strict-transport-security' = 'max-age='
    'x-content-type-options'    = 'nosniff'
    'x-frame-options'           = 'DENY'
    'referrer-policy'           = 'strict-origin-when-cross-origin'
    'permissions-policy'        = 'camera=()'
}
foreach ($k in $required.Keys) {
    Assert-That "Header $k" ((Get-Header $root $k) -like "*$($required[$k])*") "(got '$(Get-Header $root $k)')"
}

# 4. Hashed static bundle: long cache, gzip, still has security headers.
$m = [regex]::Match($root.Body, 'src="\.?(/static/js/main\.[0-9a-f]+\.js)"')
Assert-That 'index.html references /static/js/main.<hash>.js' $m.Success
if ($m.Success) {
    $js = Invoke-Get $m.Groups[1].Value -Gzip
    Assert-That "GET $($m.Groups[1].Value) -> 200" ($js.Status -eq 200) "(status=$($js.Status))"
    Assert-That 'Static Cache-Control immutable' ((Get-Header $js 'cache-control') -like '*immutable*') "(got '$(Get-Header $js 'cache-control')')"
    Assert-That 'Static Content-Encoding gzip' ((Get-Header $js 'content-encoding') -eq 'gzip') "(got '$(Get-Header $js 'content-encoding')')"
    Assert-That 'Static keeps security headers' ((Get-Header $js 'x-content-type-options') -eq 'nosniff')
}

# 5. SPA fallback and real 404s.
$spa = Invoke-Get '/some/client/route'
Assert-That 'SPA fallback /some/client/route -> 200 HTML' ($spa.Status -eq 200 -and $spa.Body -like "*$ExpectText*") "(status=$($spa.Status))"
$missing = Invoke-Get '/static/js/does-not-exist.js'
Assert-That 'Missing static asset -> 404' ($missing.Status -eq 404) "(status=$($missing.Status))"
$dot = Invoke-Get '/.env'
Assert-That 'Dotfile /.env -> 404' ($dot.Status -eq 404) "(status=$($dot.Status))"

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
if ($script:failures -gt 0) {
    Write-Host "RESULT: FAIL ($script:failures check(s) failed)" -ForegroundColor Red
    exit 1
}
Write-Host 'RESULT: PASS' -ForegroundColor Green
exit 0
