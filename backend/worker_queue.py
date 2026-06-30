from queue import Queue, Full, Empty
from threading import Thread, Event
from typing import Dict, Any
import time
from database import SessionLocal
from models import dbEvent
from datetime import datetime

NUM_SHARDS = 3
QUEUE_SIZE = 100
WORKERS_PER_SHARD = 3

# One queue per Postgres shard
stateful_queues = {
    shard_id: Queue(maxsize=QUEUE_SIZE)
    for shard_id in range(NUM_SHARDS)
}

# add stateless queues for read operations

stop_event = Event()
worker_threads = []

# Simple metric
shed_requests = {
    shard_id: 0
    for shard_id in range(NUM_SHARDS)
}


def write_to_postgres(shard_id: int, data: dict):
    print("writting to shard-",shard_id)
    db = SessionLocal()

    try:
        event = dbEvent(
            city=data["city"],
            address=data["address"],
            sport=data["sport"],
            level=data.get("level", 1),
            event_time=data.get("event_time", datetime.now()),
            capacity=data.get("capacity", 10),
            joined_count=data.get("joined_count", 0),
        )

        # Insert the event 
        db.add(event)

        # Commit the change
        db.commit()

        # Reload the object from the database so generated values
        # such as id or created_at are available in Python.
        db.refresh(event)

        print(f"Inserted event {event.id} into shard {shard_id}")

    except Exception as e:
        db.rollback()
        print(f"Insert failed: {e}")

    finally:
        db.close()


def worker_loop(shard_id: int):
    """
    One worker repeatedly takes tasks from one shard queue
    and writes them to the correct Postgres shard.
    """
    queue = stateful_queues[shard_id]

    while not stop_event.is_set():
        try:
            # print("waiting for tasks in shard-", shard_id)
            task = queue.get(timeout=1)
            print("waiting for tasks in shard-", shard_id)

        except Empty:
            continue

        try:
            print("Found a task in shard-", shard_id)
            write_to_postgres(shard_id, task["data"])
        except Exception as e:
            print(f"Worker error on shard {shard_id}: {e}")
        finally:
            queue.task_done()


def start_workers():
    """
    Starts workers once when FastAPI starts.
    """
    print("Starting queue workers...")

    for shard_id in range(NUM_SHARDS):
        for worker_id in range(WORKERS_PER_SHARD):
            thread = Thread(
                target=worker_loop,
                args=(shard_id,),
                daemon=True,                                     # Allows Python to exit even if this background worker is still running
                name=f"worker-shard-{shard_id}-{worker_id}",
            )
            thread.start()
            worker_threads.append(thread)

    print(f"Started {len(worker_threads)} workers.")


def stop_workers():
    """
    Stops workers when FastAPI shuts down.
    """
    print("Stopping queue workers...")
    stop_event.set()


def enqueue_request(shard_id: int, task_type: str, task_dict: Dict[str, Any]) -> bool:
    """
    Try to enqueue a request.
    Return True if accepted.
    Return False if queue is full.
    """
    task = {
        "task_type": task_type,
        "data": task_dict,
    }

    try:
        stateful_queues[shard_id].put_nowait(task)
        print("Enqued task: ", task, " into the shard-", shard_id)
        return True
    except Full:
        shed_requests[shard_id] += 1
        return False


def get_queue_metrics():
    return {
        shard_id: {
            "queue_size": queue.qsize(),
            "queue_capacity": QUEUE_SIZE,
            "shed_requests": shed_requests[shard_id],
            "workers": WORKERS_PER_SHARD,
        }
        for shard_id, queue in stateful_queues.items()
    }