from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import socket
from database import engine
import models
from routers import auth
from typing import Optional
from contextlib import asynccontextmanager
from fastapi import HTTPException
from datetime import datetime

from worker_queue import (
    start_workers,
    stop_workers,
    enqueue_request,
    get_queue_metrics,
)
# Create the tables if they don't exist yet
models.Base.metadata.create_all(bind=engine)

@asynccontextmanager
async def lifespan(app: FastAPI):
    start_workers()
    yield
    stop_workers()


app = FastAPI(title="Gamba API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173"],  # allow frontend requests
    allow_credentials=True,
    allow_methods=["*"], 
    allow_headers=["*"],  
)

app.include_router(auth.router)

@app.get("/health")
def health_check():
    """
    Health check endpoint. 
    Returns the hostname so we can verify round-robin load balancing later.
    """
    return {
        "status": "ok", 
        "node_id": socket.gethostname()
    }


import hashlib
NUM_SHARDS = 3
def get_shard_id(location, category, num_shards: int = NUM_SHARDS) -> int:
    key = f"{location}\x1f{category}"

    digest = hashlib.blake2b(
        key.encode("utf-8"),
        digest_size=8
    ).digest()

    return int.from_bytes(digest, "big") % num_shards
    
@app.post("/event")
def post_event(
    city: str,
    address: str,
    sport: str,
    level: int = 1,
    capacity: int = 10,
):
    
    # The idea is to enqueue the task
    # so that a controlled number of workers will connect to the db 
    # and process the tasks in their tempo (constant work)
    
    shard_id = 0  # for now, test with shard 0 first

    print("POST /event was called")

    enqueued = enqueue_request(
        shard_id=shard_id,
        task_type="POST",
        task_dict={
            "city": city,
            "address": address,
            "sport": sport,
            "level": level,
            "event_time": datetime.now(),
            "capacity": capacity,
            "joined_count": 0,
        },
    )

    print("enqueue_request returned:", enqueued)

    if not enqueued:
        raise HTTPException(
            status_code=503,
            detail=f"Shard {shard_id} queue is full",
        )

    return {
        "status": "accepted",
        "shard_id": shard_id,
        "enqueued": True,
    }


@app.get("/metrics")
def metrics():
    return get_queue_metrics()

@app.get("/event")
def get_event(
    customer_id: int,
    location: Optional[str] = None,
    category: Optional[str] = None,
    limit: int = 10
):
    
    """
    Provision of events endpoint.
    Returns a list of events based on the parameters.
    """

    # check the rate limit for the customer


    # The idea is to enque the request into reading / stateless queue to get the events

    # At first I will ignore caches. Emirhan wants to implement them.
    # first check local cache
    # then check remote cache

    # then ask database

    # find in which shard the data is stored
    shard_id = get_shard_id(location, category)
    enqueue_request(shard_id, task_type ="GET", task_dict={"location":location, "category":category})

    
    return {
        "customer_id": customer_id,
        "location": location,
        "category": category,
        "limit": limit
    }