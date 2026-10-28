#!/bin/sh
# Smoke test for the portfolio container (local or deployed). POSIX sh + curl.
#
# Usage: sh scripts/smoke.sh [BASE_URL]
#   BASE_URL defaults to $SMOKE_BASE_URL, then http://localhost:8080
# Exits 1 if any check fails.
set -eu

BASE_URL="${1:-${SMOKE_BASE_URL:-http://localhost:8080}}"
BASE_URL="${BASE_URL%/}"
EXPECT_TEXT="${EXPECT_TEXT:-Dat Nguyen}"
RETRIES="${RETRIES:-10}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
FAILURES=0

# fetch <path> [extra curl args...] -> sets STATUS, writes $TMP/h and $TMP/b
fetch() {
  path="$1"; shift
  STATUS="$(curl -sS --max-time 10 -A portfolio-smoke/1.0 -D "$TMP/h" -o "$TMP/b" \
    -w '%{http_code}' "$@" "$BASE_URL$path" 2>/dev/null)" || STATUS=000
}

# header <name> -> value of the header from the last fetch (case-insensitive)
header() {
  grep -i "^$1:" "$TMP/h" | head -n1 | cut -d: -f2- | sed 's/^ *//' | tr -d '\r'
}

check() {
  name="$1"; shift
  if "$@"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name"
    FAILURES=$((FAILURES + 1))
  fi
}

echo "Smoke test against $BASE_URL"

# 1. Health (retry while the container starts).
i=0
while [ "$i" -lt "$RETRIES" ]; do
  fetch /healthz
  [ "$STATUS" = 200 ] && break
  i=$((i + 1)); sleep 2
done
check 'GET /healthz -> 200 "ok"' sh -c "[ '$STATUS' = 200 ] && grep -qx ok '$TMP/b'"
if [ "$STATUS" = 000 ]; then echo 'Service unreachable, aborting.'; exit 1; fi

# 2. HTML shell.
fetch /
cp "$TMP/b" "$TMP/index.html"
check 'GET / -> 200'                 [ "$STATUS" = 200 ]
check 'GET / is text/html'           sh -c "echo '$(header content-type)' | grep -q '^text/html'"
check "GET / contains '$EXPECT_TEXT'" grep -q "$EXPECT_TEXT" "$TMP/b"
check 'GET / Cache-Control: no-cache' [ "$(header cache-control)" = no-cache ]
check 'Server header hides nginx version' sh -c "! echo '$(header server)' | grep -q '[0-9]'"
check 'No inline <script> blocks'    sh -c "! grep -q '<script>[^<]' '$TMP/b'"

# 3. Security headers.
check 'Header content-security-policy'   sh -c "echo \"\$0\" | grep -q \"default-src 'self'\"" "$(header content-security-policy)"
check 'Header strict-transport-security' sh -c "echo '$(header strict-transport-security)' | grep -q 'max-age='"
check 'Header x-content-type-options'    [ "$(header x-content-type-options)" = nosniff ]
check 'Header x-frame-options'           [ "$(header x-frame-options)" = DENY ]
check 'Header referrer-policy'           [ "$(header referrer-policy)" = strict-origin-when-cross-origin ]
check 'Header permissions-policy'        sh -c "echo '$(header permissions-policy)' | grep -q 'camera=()'"

# 4. Hashed static bundle: long cache, gzip, still has security headers.
MAIN_JS="$(grep -o 'src="\.\{0,1\}/static/js/main\.[0-9a-f]*\.js"' "$TMP/index.html" | head -n1 | sed 's/^src="\.\{0,1\}//; s/"$//')"
check 'index.html references /static/js/main.<hash>.js' [ -n "$MAIN_JS" ]
if [ -n "$MAIN_JS" ]; then
  fetch "$MAIN_JS" -H 'Accept-Encoding: gzip'
  check "GET $MAIN_JS -> 200"           [ "$STATUS" = 200 ]
  check 'Static Cache-Control immutable' sh -c "echo '$(header cache-control)' | grep -q immutable"
  check 'Static Content-Encoding gzip'   [ "$(header content-encoding)" = gzip ]
  check 'Static keeps security headers'  [ "$(header x-content-type-options)" = nosniff ]
fi

# 5. SPA fallback and real 404s.
fetch /some/client/route
check 'SPA fallback /some/client/route -> 200 HTML' sh -c "[ '$STATUS' = 200 ] && grep -q '$EXPECT_TEXT' '$TMP/b'"
fetch /static/js/does-not-exist.js
check 'Missing static asset -> 404' [ "$STATUS" = 404 ]
fetch /.env
check 'Dotfile /.env -> 404' [ "$STATUS" = 404 ]

if [ "$FAILURES" -gt 0 ]; then
  echo "RESULT: FAIL ($FAILURES check(s) failed)"
  exit 1
fi
echo 'RESULT: PASS'
