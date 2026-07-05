from prometheus_client import Counter, Gauge, Histogram

requests_total = Counter(
    "gamba_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

request_duration = Histogram(
    "gamba_request_duration_seconds",
    "HTTP request duration in seconds",
    ["endpoint"],
)

cache_hits = Counter("gamba_cache_hits_total", "Redis cache hits")
cache_misses = Counter("gamba_cache_misses_total", "Redis cache misses")
rate_limited = Counter("gamba_rate_limited_total", "429 responses served")
load_shed = Counter(
    "gamba_load_shed_total",
    "503 responses served by load shedding",
    ["reason"],
)
in_flight_requests = Gauge(
    "gamba_in_flight_requests",
    "Requests currently being processed by the backend",
)
latency_ewma_ms = Gauge(
    "gamba_latency_ewma_ms",
    "Exponentially weighted moving average of backend request latency in milliseconds",
)
