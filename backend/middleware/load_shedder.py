import os
import random
import time
from threading import Lock

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

import metrics


LOAD_SHEDDING_ENABLED = os.getenv("LOAD_SHEDDING_ENABLED", "false").lower() == "true"
MAX_IN_FLIGHT_REQUESTS = int(os.getenv("MAX_IN_FLIGHT_REQUESTS", "200"))
MAX_AVG_LATENCY_MS = float(os.getenv("MAX_AVG_LATENCY_MS", "1200"))
LATENCY_SHED_PROBABILITY = float(os.getenv("LATENCY_SHED_PROBABILITY", "0.5"))
LATENCY_EWMA_ALPHA = float(os.getenv("LATENCY_EWMA_ALPHA", "0.1"))
BYPASS_PATHS = {"/health", "/metrics"}


class LoadSheddingMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._in_flight = 0
        self._latency_ewma_ms = 0.0
        self._has_latency_sample = False
        self._lock = Lock()

    async def dispatch(self, request: Request, call_next):
        if not LOAD_SHEDDING_ENABLED or request.url.path in BYPASS_PATHS:
            return await call_next(request)

        with self._lock:
            if self._in_flight >= MAX_IN_FLIGHT_REQUESTS:
                metrics.load_shed.labels("in_flight").inc()
                return JSONResponse(
                    {"detail": "Service overloaded", "reason": "in_flight"},
                    status_code=503,
                    headers={"Retry-After": "1"},
                )

            if (
                self._has_latency_sample
                and self._latency_ewma_ms > MAX_AVG_LATENCY_MS
                and random.random() < LATENCY_SHED_PROBABILITY * (self._latency_ewma_ms / MAX_AVG_LATENCY_MS)
            ):
                metrics.load_shed.labels("latency").inc()
                return JSONResponse(
                    {"detail": "Service overloaded", "reason": "latency"},
                    status_code=503,
                    headers={"Retry-After": "1"},
                )

            self._in_flight += 1
            metrics.in_flight_requests.set(self._in_flight)

        start = time.monotonic()
        try:
            return await call_next(request)
        finally:
            duration_ms = (time.monotonic() - start) * 1000

            with self._lock:
                self._in_flight -= 1
                metrics.in_flight_requests.set(self._in_flight)

                if self._has_latency_sample:
                    self._latency_ewma_ms = (
                        (1 - LATENCY_EWMA_ALPHA) * self._latency_ewma_ms
                        + LATENCY_EWMA_ALPHA * duration_ms
                    )
                else:
                    self._latency_ewma_ms = duration_ms
                    self._has_latency_sample = True

                metrics.latency_ewma_ms.set(self._latency_ewma_ms)
