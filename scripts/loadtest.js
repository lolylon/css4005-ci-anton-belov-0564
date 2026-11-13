// k6 load test for spiky traffic pattern — ramp up hard, hold, ramp down.
// Usage: k6 run -e BASE_URL=https://YOUR_ALB_DNS scripts/loadtest.js
import http from "k6/http";
import { check, sleep } from "k6";

export const options = {
  stages: [
    { duration: "30s", target: 5 },
    { duration: "1m", target: 40 },  // spike
    { duration: "2m", target: 40 },
    { duration: "1m", target: 5 },
    { duration: "30s", target: 0 },
  ],
  thresholds: {
    http_req_failed: ["rate<0.05"],
  },
};

const BASE = __ENV.BASE_URL;

export default function () {
  const res = http.get(`${BASE}/readyz`);
  check(res, { "readyz 200": (r) => r.status === 200 });

  const create = http.post(
    `${BASE}/api/items`,
    JSON.stringify({
      title: `Book ${__ITER}`,
      description: "Library books load test",
    }),
    { headers: { "Content-Type": "application/json" } }
  );
  check(create, { "create 201": (r) => r.status === 201 });
  sleep(0.3);
}
