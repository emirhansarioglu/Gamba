import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';
http.setResponseCallback(http.expectedStatuses({ min: 200, max: 399 }, 409));

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const SPOOF_IPS = (__ENV.SPOOF_IPS || 'true').toLowerCase() !== 'false';
const PASSWORD = __ENV.PASSWORD || 'testpass123';
const RUN_ID = __ENV.RUN_ID || `${Date.now()}`;
const READ_VUS = Number(__ENV.READ_VUS || '250');
const JOIN_VUS = Number(__ENV.JOIN_VUS || '250');
const EVENT_COUNT = Number(__ENV.EVENT_COUNT || '200');
const EVENT_CAPACITY = Number(__ENV.EVENT_CAPACITY || '100000');
const READ_DAYS = Number(__ENV.READ_DAYS || '365');
const RAMP_UP = __ENV.RAMP_UP || '30s';
const HOLD = __ENV.HOLD || '90s';
const RAMP_DOWN = __ENV.RAMP_DOWN || '30s';
const SLEEP_SECONDS = Number(__ENV.SLEEP_SECONDS || '1.05');
const DEBUG_FAILURES = (__ENV.DEBUG_FAILURES || 'false').toLowerCase() === 'true';

const cities = [
  'Berlin', 'Potsdam', 'Hamburg', 'Leipzig', 'Munich', 'Cologne', 'Dresden', 'Bremen',
  'Hanover', 'Stuttgart', 'Frankfurt', 'Dortmund', 'Essen', 'Bonn', 'Mainz', 'Aachen',
];
const sports = [
  'Football', 'Basketball', 'Tennis', 'Volleyball', 'Running', 'Cycling', 'Handball',
  'Badminton', 'Swimming', 'Climbing', 'Table tennis', 'Hockey',
];

const readRateLimited = new Counter('db_read_rate_limited');
const readLoadShed = new Counter('db_read_load_shed');
const readClientErrors = new Counter('db_read_client_errors');
const readServerErrors = new Counter('db_read_server_errors');
const joinCreated = new Counter('db_join_created');
const joinConflicts = new Counter('db_join_conflicts');
const joinRateLimited = new Counter('db_join_rate_limited');
const joinLoadShed = new Counter('db_join_load_shed');
const joinClientErrors = new Counter('db_join_client_errors');
const joinServerErrors = new Counter('db_join_server_errors');

let playerToken;

export const options = {
  scenarios: {
    cache_miss_reads: {
      executor: 'ramping-vus',
      exec: 'cacheMissReads',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: Math.max(1, READ_VUS) },
        { duration: HOLD, target: Math.max(1, READ_VUS) },
        { duration: RAMP_DOWN, target: 0 },
      ],
    },
    join_writes: {
      executor: 'ramping-vus',
      exec: 'joinWrites',
      startVUs: 0,
      stages: [
        { duration: RAMP_UP, target: Math.max(1, JOIN_VUS) },
        { duration: HOLD, target: Math.max(1, JOIN_VUS) },
        { duration: RAMP_DOWN, target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<3000'],
    http_req_failed: ['rate<0.2'],
  },
};

function virtualUserIp() {
  const vuIndex = Math.max(__VU - 1, 0);
  const thirdOctet = Math.floor(vuIndex / 250);
  const fourthOctet = (vuIndex % 250) + 1;
  return `10.20.${thirdOctet}.${fourthOctet}`;
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

function authHeaders(token) {
  return headers({ Authorization: `Bearer ${token}` });
}

function postJson(url, body, token, name) {
  const requestHeaders = token ? authHeaders(token) : headers();
  return http.post(url, JSON.stringify(body), {
    headers: requestHeaders,
    tags: { name },
  });
}

function registerAndLogin(username, role) {
  postJson(
    `${BASE_URL}/api/auth/register`,
    { username, password: PASSWORD, role },
    null,
    'POST /api/auth/register',
  );

  const loginRes = postJson(
    `${BASE_URL}/api/auth/login`,
    { username, password: PASSWORD },
    null,
    'POST /api/auth/login',
  );

  check(loginRes, { 'login status 200': (r) => r.status === 200 });

  if (loginRes.status !== 200) {
    if (DEBUG_FAILURES) {
      console.log(`login failed status=${loginRes.status} body=${loginRes.body}`);
    }
    return null;
  }

  return loginRes.json('access_token');
}

function eventPayload(index) {
  const eventDate = new Date(Date.now() + ((index % READ_DAYS) + 1) * 24 * 60 * 60 * 1000);
  return {
    city: cities[index % cities.length],
    address: `Load test court ${index}`,
    sport: sports[index % sports.length],
    level: (index % 5) + 1,
    event_time: eventDate.toISOString(),
    capacity: EVENT_CAPACITY,
  };
}

export function setup() {
  const organizerUsername = `dbheavy_org_${RUN_ID}`;
  const organizerToken = registerAndLogin(organizerUsername, 'organizer');
  if (!organizerToken) {
    throw new Error('Could not create organizer for DB-heavy setup');
  }

  const eventIds = [];
  for (let i = 0; i < EVENT_COUNT; i += 1) {
    const res = postJson(
      `${BASE_URL}/api/events`,
      eventPayload(i),
      organizerToken,
      'POST /api/events',
    );

    if (res.status === 201) {
      eventIds.push(res.json('id'));
    } else if (DEBUG_FAILURES) {
      console.log(`event setup failed status=${res.status} body=${res.body}`);
    }
  }

  if (eventIds.length === 0) {
    throw new Error('Could not create any events for DB-heavy setup');
  }

  return { eventIds };
}

function ensurePlayerToken() {
  if (!playerToken) {
    playerToken = registerAndLogin(`dbheavy_player_${RUN_ID}_${__VU}`, 'player');
  }
  return playerToken;
}

function recordReadStatus(res) {
  if (res.status === 429) {
    readRateLimited.add(1);
  } else if (res.status === 503) {
    readLoadShed.add(1);
  } else if (res.status >= 400 && res.status < 500) {
    readClientErrors.add(1);
  } else if (res.status >= 500) {
    readServerErrors.add(1);
  }
}

function recordJoinStatus(res) {
  if (res.status === 200) {
    joinCreated.add(1);
  } else if (res.status === 409) {
    joinConflicts.add(1);
  } else if (res.status === 429) {
    joinRateLimited.add(1);
  } else if (res.status === 503) {
    joinLoadShed.add(1);
  } else if (res.status >= 400 && res.status < 500) {
    joinClientErrors.add(1);
  } else if (res.status >= 500) {
    joinServerErrors.add(1);
  }
}

export function cacheMissReads() {
  const token = ensurePlayerToken();
  if (!token) {
    sleep(SLEEP_SECONDS);
    return;
  }

  const variant = (__VU * 1000003 + __ITER) % (cities.length * sports.length * READ_DAYS);
  const city = cities[variant % cities.length];
  const sport = sports[Math.floor(variant / cities.length) % sports.length];
  const dayOffset = Math.floor(variant / (cities.length * sports.length)) % READ_DAYS;
  const day = new Date(Date.now() + (dayOffset + 1) * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

  const res = http.get(
    `${BASE_URL}/api/events?city=${encodeURIComponent(city)}&sport=${encodeURIComponent(sport)}&day=${day}`,
    {
      headers: authHeaders(token),
      tags: { name: 'GET /api/events' },
    },
  );

  check(res, { 'db read status 200': (r) => r.status === 200 });
  recordReadStatus(res);

  if (DEBUG_FAILURES && res.status !== 200 && Math.random() < 0.01) {
    console.log(`db read failed status=${res.status} body=${res.body}`);
  }

  sleep(SLEEP_SECONDS);
}

export function joinWrites(data) {
  const token = ensurePlayerToken();
  if (!token) {
    sleep(SLEEP_SECONDS);
    return;
  }

  const eventIds = data.eventIds;
  const eventId = eventIds[(__VU * 997 + __ITER) % eventIds.length];
  const res = postJson(
    `${BASE_URL}/api/events/${eventId}/join`,
    {},
    token,
    'POST /api/events/{id}/join',
  );

  check(res, { 'join status 200 or 409': (r) => r.status === 200 || r.status === 409 });
  recordJoinStatus(res);

  if (DEBUG_FAILURES && ![200, 409].includes(res.status) && Math.random() < 0.01) {
    console.log(`join failed status=${res.status} body=${res.body}`);
  }

  sleep(SLEEP_SECONDS);
}