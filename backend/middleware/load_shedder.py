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
IN_FLIGHT_HARD_LIMIT = int(os.getenv("IN_FLIGHT_HARD_LIMIT", str(MAX_IN_FLIGHT_REQUESTS)))
IN_FLIGHT_SOFT_LIMIT = int(os.getenv("IN_FLIGHT_SOFT_LIMIT", str(int(IN_FLIGHT_HARD_LIMIT * 0.8))))
MAX_AVG_LATENCY_MS = float(os.getenv("MAX_AVG_LATENCY_MS", "1200"))
LATENCY_SHED_PROBABILITY = float(os.getenv("LATENCY_SHED_PROBABILITY", "0.5"))
LATENCY_EWMA_ALPHA = float(os.getenv("LATENCY_EWMA_ALPHA", "0.2"))
MAX_PROCESS_CPU_PERCENT = float(
    os.getenv("MAX_PROCESS_CPU_PERCENT", os.getenv("MAX_CPU_PERCENT", "185"))
)
CPU_SHED_PROBABILITY = float(os.getenv("CPU_SHED_PROBABILITY", "0.5"))
CPU_EWMA_ALPHA = float(os.getenv("CPU_EWMA_ALPHA", "0.2"))
CPU_SAMPLE_INTERVAL_SECONDS = float(os.getenv("CPU_SAMPLE_INTERVAL_SECONDS", "1"))
MAX_SHED_PROBABILITY = float(os.getenv("MAX_SHED_PROBABILITY", "1.0"))
BYPASS_PATHS = {"/health", "/metrics"}


class LoadSheddingMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._in_flight = 0
        self._latency_ewma_ms = 0.0
        self._has_latency_sample = False
        self._cpu_ewma_percent = 0.0
        self._has_cpu_sample = False
        self._last_cpu_sample_at = time.monotonic()
        self._last_process_cpu_seconds = time.process_time()
        self._lock = Lock()

    def _refresh_cpu_sample(self):
        now = time.monotonic()
        elapsed_seconds = now - self._last_cpu_sample_at
        if elapsed_seconds < CPU_SAMPLE_INTERVAL_SECONDS:
            return

        process_cpu_seconds = time.process_time()
        cpu_delta_seconds = process_cpu_seconds - self._last_process_cpu_seconds
        cpu_percent = max(0.0, 100 * cpu_delta_seconds / elapsed_seconds)

        if self._has_cpu_sample:
            self._cpu_ewma_percent = (
                (1 - CPU_EWMA_ALPHA) * self._cpu_ewma_percent
                + CPU_EWMA_ALPHA * cpu_percent
            )
        else:
            self._cpu_ewma_percent = cpu_percent
            self._has_cpu_sample = True

        self._last_cpu_sample_at = now
        self._last_process_cpu_seconds = process_cpu_seconds
        metrics.cpu_ewma_percent.set(self._cpu_ewma_percent)

    @staticmethod
    def _excess_probability(base_probability, current_value, threshold):
        if threshold <= 0:
            return 1.0

        excess_ratio = (current_value - threshold) / threshold
        return min(1.0, base_probability * max(0.0, excess_ratio))

    @staticmethod
    def _pressure_between(current_value, soft_limit, hard_limit):
        if hard_limit <= soft_limit:
            return 1.0 if current_value >= hard_limit else 0.0

        pressure = (current_value - soft_limit) / (hard_limit - soft_limit)
        return min(1.0, max(0.0, pressure))

    @staticmethod
    def _cap_shed_probability(probability):
        return min(MAX_SHED_PROBABILITY, max(0.0, probability))

    async def dispatch(self, request: Request, call_next):
        if not LOAD_SHEDDING_ENABLED or request.url.path in BYPASS_PATHS:
            return await call_next(request)

        with self._lock:
            self._refresh_cpu_sample()
            in_flight_pressure = self._pressure_between(
                self._in_flight,
                IN_FLIGHT_SOFT_LIMIT,
                IN_FLIGHT_HARD_LIMIT,
            )

            cpu_pressure = 0.0
            if self._has_cpu_sample and self._cpu_ewma_percent > MAX_PROCESS_CPU_PERCENT:
                cpu_pressure = self._excess_probability(
                    CPU_SHED_PROBABILITY,
                    self._cpu_ewma_percent,
                    MAX_PROCESS_CPU_PERCENT,
                )

            latency_pressure = 0.0
            if self._has_latency_sample and self._latency_ewma_ms > MAX_AVG_LATENCY_MS:
                latency_pressure = self._excess_probability(
                    LATENCY_SHED_PROBABILITY,
                    self._latency_ewma_ms,
                    MAX_AVG_LATENCY_MS,
                )

            shed_reason, shed_probability = max(
                (
                    ("in_flight", in_flight_pressure),
                    ("cpu", cpu_pressure),
                    ("latency", latency_pressure),
                ),
                key=lambda item: item[1],
            )
            shed_probability = self._cap_shed_probability(shed_probability)

            if shed_probability > 0 and random.random() < shed_probability:
                metrics.load_shed.labels(shed_reason).inc()
                return JSONResponse(
                    {"detail": "Service overloaded", "reason": shed_reason},
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
