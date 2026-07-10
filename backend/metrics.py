from prometheus_client import Counter, Gauge, Histogram

requests_total = Counter(
    "gamba_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

request_duration = Histogram(
    "gamba_request_duration_seconds",
    "HTTP request duration in seconds",
    ["endpoint", "status"],
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

db_query_duration = Histogram(
    "gamba_db_query_duration_seconds",
    "Database cursor execution duration in seconds",
    ["operation"],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5),
)
db_queries = Counter(
    "gamba_db_queries_total",
    "Database queries executed by the backend",
    ["operation", "outcome"],
)
db_pool_checked_out = Gauge(
    "gamba_db_pool_checked_out",
    "Database connections currently checked out from this backend pool",
)
