import time
from threading import Lock
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
import metrics

BUCKET_CAPACITY = 60
REFILL_RATE = 1.0  # tokens per second


class TokenBucketMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._buckets = {}
        self._lock = Lock()

    async def dispatch(self, request: Request, call_next):
        ip = request.client.host if request.client else "unknown"

        with self._lock:
            now = time.monotonic()
            if ip not in self._buckets:
                self._buckets[ip] = {"tokens": BUCKET_CAPACITY, "last": now}

            bucket = self._buckets[ip]
            elapsed = now - bucket["last"]
            bucket["tokens"] = min(BUCKET_CAPACITY, bucket["tokens"] + elapsed * REFILL_RATE)
            bucket["last"] = now

            if bucket["tokens"] < 1:
                metrics.rate_limited.inc()
                return JSONResponse({"detail": "Too many requests"}, status_code=429)

            bucket["tokens"] -= 1

        return await call_next(request)
