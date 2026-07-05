import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const SPOOF_IPS = (__ENV.SPOOF_IPS || 'true').toLowerCase() !== 'false';
const TODAY = new Date().toISOString().slice(0, 10);
const PASSWORD = 'testpass123';
const DEBUG_FAILURES = (__ENV.DEBUG_FAILURES || 'false').toLowerCase() === 'true';

const readRateLimited = new Counter('read_rate_limited');
const readLoadShedInFlight = new Counter('read_load_shed_in_flight');
const readLoadShedLatency = new Counter('read_load_shed_latency');
const readLoadShedUnknown = new Counter('read_load_shed_unknown');
const readClientErrors = new Counter('read_client_errors');
const readServerErrors = new Counter('read_server_errors');
const readUnexpectedStatus = new Counter('read_unexpected_status');

let token;

function virtualUserIp() {
  const vuIndex = __VU - 1;
  const thirdOctet = Math.floor(vuIndex / 250);
  const fourthOctet = (vuIndex % 250) + 1;

  return `10.10.${thirdOctet}.${fourthOctet}`;
}

function headers(extra = {}) {
  const result = {
    'Content-Type': 'application/json',
    ...extra,
  };

  if (SPOOF_IPS) {
    result['X-Forwarded-For'] = virtualUserIp();
  }

  return result;
}

function loadShedReason(res) {
  try {
    return res.json('reason') || 'unknown';
  } catch {
    return 'unknown';
  }
}

export const options = {
  scenarios: {
    read_heavy: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 10 },
        { duration: '60s', target: 100 },
        { duration: '60s', target: 500 },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

function login() {
  const username = `loadtest_${__VU}_${Date.now()}`;

  http.post(
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ username, password: PASSWORD, role: 'player' }),
    { headers: headers(), tags: { name: 'POST /api/auth/register' } },
  );

  const res = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username, password: PASSWORD }),
    { headers: headers(), tags: { name: 'POST /api/auth/login' } },
  );

  check(res, { 'login status 200': (r) => r.status === 200 });

  return res.json('access_token');
}

export default function () {
  if (!token) {
    token = login();
  }

  const res = http.get(
    `${BASE_URL}/api/events?city=Berlin&sport=Football&day=${TODAY}`,
    {
      headers: headers({ Authorization: `Bearer ${token}` }),
      tags: { name: 'GET /api/events' },
    },
  );

  check(res, { 'status 200': (r) => r.status === 200 });

  if (res.status === 429) {
    readRateLimited.add(1);
  } else if (res.status === 503) {
    const reason = loadShedReason(res);

    if (reason === 'in_flight') {
      readLoadShedInFlight.add(1);
    } else if (reason === 'latency') {
      readLoadShedLatency.add(1);
    } else {
      readLoadShedUnknown.add(1);
    }
  } else if (res.status >= 400 && res.status < 500) {
    readClientErrors.add(1);
  } else if (res.status >= 500) {
    readServerErrors.add(1);
  } else if (res.status !== 200) {
    readUnexpectedStatus.add(1);
  }

  if (DEBUG_FAILURES && res.status !== 200 && Math.random() < 0.01) {
    console.log(`GET /api/events failed status=${res.status} ip=${virtualUserIp()} body=${res.body}`);
  }

  sleep(0.1);   // the problem is that the refil rate is 1 req/sec -> most of the requests will be limited
  //therefore it is adjusted to 0.9
}
