import os
import socket
import time
import logging
import json
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from database import engine
import models
import metrics
from routers import auth, events
from middleware.rate_limiter import TokenBucketMiddleware

models.Base.metadata.create_all(bind=engine)

ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", "http://localhost:5173").split(",")
NODE_ID = socket.gethostname()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("gamba")

app = FastAPI(title="Gamba API")

# Middleware order: last add_middleware runs first on incoming requests.
# Stack: TokenBucket → CORS → routes
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(TokenBucketMiddleware)

app.include_router(auth.router)
app.include_router(events.router)


@app.middleware("http")
async def observe(request: Request, call_next):
    start = time.monotonic()
    response = await call_next(request)
    duration = time.monotonic() - start

    endpoint = request.url.path
    metrics.requests_total.labels(request.method, endpoint, str(response.status_code)).inc()
    metrics.request_duration.labels(endpoint).observe(duration)

    logger.info(json.dumps({
        "node_id": NODE_ID,
        "method": request.method,
        "path": endpoint,
        "status": response.status_code,
        "duration_ms": round(duration * 1000, 1),
    }))

    return response


@app.get("/health")
def health_check():
    return {"status": "ok", "node_id": NODE_ID}


@app.get("/metrics")
def prometheus_metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
