// Task 13: load test against the SLOs (R6).
//
// 50 VUs for 2 minutes (constant), through Cloudflare to the live site.
// Each iteration is one page view: GET / (HTML, no-cache, always reaches the origin), the hashed JS and CSS
// bundles (immutable, usually Cloudflare cache HITs) and GET /healthz (no-store, always origin).
// Think time is 3-5 s per page view, so the origin sees at most about 1,400 requests/minute (2 origin
// requests per view; the bundles are Cloudflare HITs), below the ALBRequestCountPerTarget scaling target
// (1,000 per target per minute with 2 tasks). Scaling load is Task 14.
//
// SLOs (requirements R6): availability 99.9 %, p95 latency < 300 ms, error rate < 0.1 %.
// k6 measures latency at the client, so it includes the client -> Cloudflare -> ALB network path. The
// origin p95 (ALB TargetResponseTime) is checked separately in CloudWatch.
//
// Run (pwsh, repo root):
//   docker run --rm -v "${PWD}/scripts/k6:/scripts:ro" -v "${PWD}/evidence/raw:/out" grafana/k6:latest `
//     run --summary-export /out/k6-load-summary.json /scripts/load.js
// Optional env: -e BASE_URL=https://test.name.vn -e VUS=50 -e DURATION=2m

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Rate, Trend } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'https://test.name.vn').replace(/\/+$/, '');
const VUS = parseInt(__ENV.VUS || '50', 10);
const DURATION = __ENV.DURATION || '2m';

// Availability: share of page views where every request in the view succeeded.
const pageAvailable = new Rate('page_available');
// Cloudflare cache status per response, tagged by request kind and cf-cache-status.
const cfCache = new Counter('cf_cache_responses');
// Request duration by cf-cache-status (edge-served HIT vs origin-served MISS/DYNAMIC).
const durationByCache = new Trend('duration_by_cache', true);

export const options = {
  scenarios: {
    load: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
      gracefulStop: '10s',
    },
  },
  thresholds: {
    // Latency SLO: p95 < 300 ms, overall and per request kind.
    'http_req_duration{scenario:load}': ['p(95)<300'],
    'http_req_duration{kind:html}': ['p(95)<300'],
    'http_req_duration{kind:asset}': ['p(95)<300'],
    'http_req_duration{kind:health}': ['p(95)<300'],
    // Error-rate SLO: < 0.1 % of requests fail (non-2xx/3xx or transport error).
    'http_req_failed{scenario:load}': ['rate<0.001'],
    // Availability SLO: >= 99.9 % of page views fully successful.
    page_available: ['rate>=0.999'],
    // All functional checks must pass at the same level.
    checks: ['rate>=0.999'],
    // Always-true thresholds, only so the summary breaks responses down by Cloudflare cache status.
    'cf_cache_responses{kind:html,cf_cache:DYNAMIC}': ['count>=0'],
    'cf_cache_responses{kind:health,cf_cache:DYNAMIC}': ['count>=0'],
    'cf_cache_responses{kind:asset,cf_cache:HIT}': ['count>=0'],
    'cf_cache_responses{kind:asset,cf_cache:MISS}': ['count>=0'],
    'cf_cache_responses{kind:asset,cf_cache:EXPIRED}': ['count>=0'],
    'cf_cache_responses{kind:asset,cf_cache:REVALIDATED}': ['count>=0'],
    'duration_by_cache{cf_cache:HIT}': ['p(95)>=0'],
    'duration_by_cache{cf_cache:MISS}': ['p(95)>=0'],
    'duration_by_cache{cf_cache:DYNAMIC}': ['p(95)>=0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
  userAgent: 'k6-portfolio-load/1.0 (Task 13)',
};

// Find the current hashed bundles so the test follows each deployment.
export function setup() {
  const res = http.get(`${BASE_URL}/`, { tags: { kind: 'setup' } });
  if (res.status !== 200) {
    throw new Error(`setup: GET / returned ${res.status}`);
  }
  const assets = [...new Set(res.body.match(/static\/(?:js|css)\/main\.[0-9a-f]+\.(?:js|css)/g) || [])];
  if (assets.length === 0) {
    throw new Error('setup: no static/js or static/css bundle found in index.html');
  }
  return { assets: assets.map((a) => `${BASE_URL}/${a}`) };
}

function record(res, kind) {
  const status = (res.headers['Cf-Cache-Status'] || 'NONE').toUpperCase();
  cfCache.add(1, { kind, cf_cache: status });
  durationByCache.add(res.timings.duration, { kind, cf_cache: status });
}

export default function (data) {
  const requests = [
    ['GET', `${BASE_URL}/`, null, { tags: { kind: 'html', name: '/' } }],
    ...data.assets.map((url) => ['GET', url, null, { tags: { kind: 'asset', name: url.replace(BASE_URL, '') } }]),
    ['GET', `${BASE_URL}/healthz`, null, { tags: { kind: 'health', name: '/healthz' } }],
  ];
  const responses = http.batch(requests);

  let ok = true;
  responses.forEach((res, i) => {
    const kind = requests[i][3].tags.kind;
    record(res, kind);
    const passed = check(
      res,
      {
        [`${kind} status 200`]: (r) => r.status === 200,
        [`${kind} served by Cloudflare`]: (r) => (r.headers['Server'] || '').toLowerCase() === 'cloudflare',
      },
      { kind },
    );
    ok = ok && passed;
  });
  ok =
    check(responses[0], { 'html contains root div': (r) => r.body.includes('id="root"') }, { kind: 'html' }) && ok;
  pageAvailable.add(ok);

  sleep(3 + Math.random() * 2);
}
