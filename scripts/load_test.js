import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const SPOOF_IPS = (__ENV.SPOOF_IPS || 'true').toLowerCase() !== 'false';
const TODAY = new Date().toISOString().slice(0, 10);
const PASSWORD = 'testpass123';
const DEBUG_FAILURES = (__ENV.DEBUG_FAILURES || 'false').toLowerCase() === 'true';
const TARGET_VUS = Number(__ENV.TARGET_VUS || '500');
const RUN_ID = __ENV.RUN_ID || 'default';
const INITIAL_AUTH_BACKOFF_SECONDS = Number(__ENV.AUTH_BACKOFF_SECONDS || '1');
const MAX_AUTH_BACKOFF_SECONDS = Number(__ENV.MAX_AUTH_BACKOFF_SECONDS || '10');
const PRE_AUTH_USERS = (__ENV.PRE_AUTH_USERS || 'true').toLowerCase() !== 'false';
const AUTH_USERS = Number(__ENV.AUTH_USERS || TARGET_VUS);
const AUTH_SETUP_RETRIES = Number(__ENV.AUTH_SETUP_RETRIES || '3');
const AUTH_SETUP_PAUSE_SECONDS = Number(__ENV.AUTH_SETUP_PAUSE_SECONDS || '0.02');
const AUTH_SETUP_BATCH_SIZE = Math.max(1, Math.floor(Number(__ENV.AUTH_SETUP_BATCH_SIZE || '25')));
const SETUP_TIMEOUT = __ENV.SETUP_TIMEOUT || '20m';

const readRateLimited = new Counter('read_rate_limited');
const readLoadShedInFlight = new Counter('read_load_shed_in_flight');
const readLoadShedCpu = new Counter('read_load_shed_cpu');
const readLoadShedLatency = new Counter('read_load_shed_latency');
const readLoadShedUnknown = new Counter('read_load_shed_unknown');
const readClientErrors = new Counter('read_client_errors');
const readServerErrors = new Counter('read_server_errors');
const readUnexpectedStatus = new Counter('read_unexpected_status');
const authRequestErrors = new Counter('auth_request_errors');
const authUnexpectedStatus = new Counter('auth_unexpected_status');

let token;
let nextAuthAttemptAt = 0;
let authBackoffSeconds = INITIAL_AUTH_BACKOFF_SECONDS;

function virtualUserIp(vuNumber = __VU) {
  const vuIndex = vuNumber - 1;
  const thirdOctet = Math.floor(vuIndex / 250);
  const fourthOctet = (vuIndex % 250) + 1;

  return `10.10.${thirdOctet}.${fourthOctet}`;
}

function headers(extra = {}, vuNumber = __VU) {
  const result = {
    'Content-Type': 'application/json',
    ...extra,
  };

  if (SPOOF_IPS) {
    result['X-Forwarded-For'] = virtualUserIp(vuNumber);
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

function jsonField(res, fieldName) {
  try {
    return res.json(fieldName);
  } catch {
    return null;
  }
}

function requestFailed(res) {
  return !res || res.error || res.status === 0;
}

function alreadyRegistered(res) {
  return res && res.status === 400 && jsonField(res, 'detail') === 'Username already registered';
}

function usernameFor(vuNumber) {
  return `loadtest_${RUN_ID}_${vuNumber}`;
}

function registerRequest(vuNumber) {
  return [
    'POST',
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ username: usernameFor(vuNumber), password: PASSWORD, role: 'player' }),
    { headers: headers({}, vuNumber), tags: { name: 'POST /api/auth/register' } },
  ];
}

function loginRequest(vuNumber) {
  return [
    'POST',
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username: usernameFor(vuNumber), password: PASSWORD }),
    { headers: headers({}, vuNumber), tags: { name: 'POST /api/auth/login' } },
  ];
}

function sendRequest(request) {
  return http.request(request[0], request[1], request[2], request[3]);
}

function debugHttpFailure(label, res, vuNumber = __VU) {
  if (!DEBUG_FAILURES || Math.random() >= 0.01) {
    return;
  }

  const status = res ? res.status : 'none';
  const error = res && res.error ? res.error : '';
  const body = res && res.body ? res.body : '';
  console.log(`${label} failed status=${status} error=${error} ip=${virtualUserIp(vuNumber)} body=${body}`);
}

function tokenFromLoginResponse(res, vuNumber, recordMetrics = true) {
  if (recordMetrics) {
    check(res, { 'login status 200': (r) => r && r.status === 200 });
  }

  if (requestFailed(res)) {
    if (recordMetrics) {
      authRequestErrors.add(1);
    }
    debugHttpFailure('POST /api/auth/login', res, vuNumber);
    return null;
  }

  if (res.status !== 200) {
    if (recordMetrics) {
      authUnexpectedStatus.add(1);
    }
    debugHttpFailure('POST /api/auth/login', res, vuNumber);
    return null;
  }

  try {
    return res.json('access_token') || null;
  } catch {
    if (recordMetrics) {
      authUnexpectedStatus.add(1);
    }
    debugHttpFailure('POST /api/auth/login', res, vuNumber);
    return null;
  }
}

export const options = {
  setupTimeout: SETUP_TIMEOUT,
  scenarios: {
    read_heavy: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },
        { duration: '1m', target: TARGET_VUS },
        { duration: '1m', target: TARGET_VUS },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

function login(vuNumber = __VU, recordMetrics = true) {
  const registerRes = sendRequest(registerRequest(vuNumber));

  if (requestFailed(registerRes)) {
    if (recordMetrics) {
      authRequestErrors.add(1);
    }
    debugHttpFailure('POST /api/auth/register', registerRes, vuNumber);
    return null;
  }

  if (registerRes.status !== 201 && !alreadyRegistered(registerRes)) {
    if (recordMetrics) {
      authUnexpectedStatus.add(1);
    }
    debugHttpFailure('POST /api/auth/register', registerRes, vuNumber);
    return null;
  }

  const res = sendRequest(loginRequest(vuNumber));
  return tokenFromLoginResponse(res, vuNumber, recordMetrics);
}

function setupBatch(vuNumbers, tokens) {
  const usersWithoutTokens = vuNumbers.filter((vuNumber) => !tokens[vuNumber - 1]);

  if (usersWithoutTokens.length === 0) {
    return;
  }

  const initialLoginResponses = http.batch(usersWithoutTokens.map(loginRequest));
  const registerCandidates = [];

  for (let i = 0; i < usersWithoutTokens.length; i += 1) {
    const vuNumber = usersWithoutTokens[i];
    const loginRes = initialLoginResponses[i];

    if (requestFailed(loginRes)) {
      debugHttpFailure('POST /api/auth/login', loginRes, vuNumber);
      continue;
    }

    if (loginRes.status === 200) {
      const setupToken = tokenFromLoginResponse(loginRes, vuNumber, false);

      if (setupToken) {
        tokens[vuNumber - 1] = setupToken;
      }

      continue;
    }

    if (loginRes.status === 401) {
      registerCandidates.push(vuNumber);
      continue;
    }

    debugHttpFailure('POST /api/auth/login', loginRes, vuNumber);
  }

  if (registerCandidates.length === 0) {
    return;
  }

  const registerResponses = http.batch(registerCandidates.map(registerRequest));
  const loginCandidates = [];

  for (let i = 0; i < registerCandidates.length; i += 1) {
    const vuNumber = registerCandidates[i];
    const registerRes = registerResponses[i];

    if (requestFailed(registerRes)) {
      debugHttpFailure('POST /api/auth/register', registerRes, vuNumber);
      continue;
    }

    if (registerRes.status !== 201 && !alreadyRegistered(registerRes)) {
      debugHttpFailure('POST /api/auth/register', registerRes, vuNumber);
      continue;
    }

    loginCandidates.push(vuNumber);
  }

  if (loginCandidates.length === 0) {
    return;
  }

  const loginResponses = http.batch(loginCandidates.map(loginRequest));

  for (let i = 0; i < loginCandidates.length; i += 1) {
    const vuNumber = loginCandidates[i];
    const setupToken = tokenFromLoginResponse(loginResponses[i], vuNumber, false);

    if (setupToken) {
      tokens[vuNumber - 1] = setupToken;
    }
  }
}

export function setup() {
  const setupStartedAt = Date.now();

  if (!PRE_AUTH_USERS) {
    console.log('Setup completed: pre-auth disabled in 0.00s');
    return { tokens: [] };
  }

  const tokens = [];

  for (let firstVuNumber = 1; firstVuNumber <= AUTH_USERS; firstVuNumber += AUTH_SETUP_BATCH_SIZE) {
    const vuNumbers = [];
    const lastVuNumber = Math.min(AUTH_USERS, firstVuNumber + AUTH_SETUP_BATCH_SIZE - 1);

    for (let vuNumber = firstVuNumber; vuNumber <= lastVuNumber; vuNumber += 1) {
      vuNumbers.push(vuNumber);
    }

    for (let attempt = 1; attempt <= AUTH_SETUP_RETRIES; attempt += 1) {
      setupBatch(vuNumbers, tokens);

      if (vuNumbers.every((vuNumber) => tokens[vuNumber - 1])) {
        break;
      }

      sleep(Math.min(MAX_AUTH_BACKOFF_SECONDS, INITIAL_AUTH_BACKOFF_SECONDS * attempt));
    }

    if (AUTH_SETUP_PAUSE_SECONDS > 0) {
      sleep(AUTH_SETUP_PAUSE_SECONDS);
    }
  }

  let authenticatedUsers = 0;

  for (let vuNumber = 1; vuNumber <= AUTH_USERS; vuNumber += 1) {
    if (tokens[vuNumber - 1]) {
      authenticatedUsers += 1;
    }
  }

  const setupSeconds = (Date.now() - setupStartedAt) / 1000;
  console.log(`Setup completed: authenticated ${authenticatedUsers}/${AUTH_USERS} users in ${setupSeconds.toFixed(2)}s with batch size ${AUTH_SETUP_BATCH_SIZE}`);

  return { tokens };
}

export default function (data) {
  if (!token) {
    if (data && data.tokens && data.tokens[__VU - 1]) {
      token = data.tokens[__VU - 1];
    }
  }

  if (!token) {
    const now = Date.now() / 1000;

    if (now < nextAuthAttemptAt) {
      sleep(Math.min(1, nextAuthAttemptAt - now));
      return;
    }

    token = login(__VU);

    if (!token) {
      nextAuthAttemptAt = now + authBackoffSeconds;
      authBackoffSeconds = Math.min(MAX_AUTH_BACKOFF_SECONDS, authBackoffSeconds * 2);
      sleep(0.5);
      return;
    }

    authBackoffSeconds = INITIAL_AUTH_BACKOFF_SECONDS;
  }

  const res = http.get(
    `${BASE_URL}/api/events?city=Berlin&sport=Football&day=${TODAY}`,
    {
      headers: headers({ Authorization: `Bearer ${token}` }),
      tags: { name: 'GET /api/events' },
    },
  );

  check(res, { 'status 200': (r) => r && r.status === 200 });

  if (requestFailed(res)) {
    readUnexpectedStatus.add(1);
    debugHttpFailure('GET /api/events', res);
  } else if (res.status === 429) {
    readRateLimited.add(1);
  } else if (res.status === 503) {
    const reason = loadShedReason(res);

    if (reason === 'in_flight') {
      readLoadShedInFlight.add(1);
    } else if (reason === 'cpu') {
      readLoadShedCpu.add(1);
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

  if (!requestFailed(res) && DEBUG_FAILURES && res.status !== 200 && Math.random() < 0.01) {
    console.log(`GET /api/events failed status=${res.status} ip=${virtualUserIp()} body=${res.body || ''}`);
  }

  sleep(0.1);   // the problem is that the refil rate is 1 req/sec -> most of the requests will be limited
  //therefore it is adjusted to 0.9
}
