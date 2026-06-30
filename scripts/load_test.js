import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const TODAY = new Date().toISOString().slice(0, 10);

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

export function setup() {
  const username = `loadtest_${__VU}_${Date.now()}`;
  http.post(
    `${BASE_URL}/api/auth/register`,
    JSON.stringify({ username, password: 'testpass123', role: 'player' }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  const res = http.post(
    `${BASE_URL}/api/auth/login`,
    JSON.stringify({ username, password: 'testpass123' }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  return { token: res.json('access_token') };
}

export default function (data) {
  const headers = {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${data.token}`,
  };

  const res = http.get(
    `${BASE_URL}/api/events?city=Berlin&sport=Football&day=${TODAY}`,
    { headers },
  );

  check(res, { 'status 200': (r) => r.status === 200 });

  sleep(0.1);
}
