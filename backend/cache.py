import redis
import os
import json
from datetime import datetime

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
_client = redis.from_url(REDIS_URL, decode_responses=True)


class _DateTimeEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, datetime):
            return obj.isoformat()
        return super().default(obj)


def get_cached(key: str):
    val = _client.get(key)
    if val is not None:
        return json.loads(val)
    return None


def set_cached(key: str, value, ttl: int = 30):
    _client.setex(key, ttl, json.dumps(value, cls=_DateTimeEncoder))


def delete_cached(key: str):
    _client.delete(key)
