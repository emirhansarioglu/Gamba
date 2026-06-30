from prometheus_client import Counter, Histogram

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
