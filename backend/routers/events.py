from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from database import SessionLocal
from datetime import date, datetime, timedelta
from typing import Optional
import models
import schemas
import cache
import metrics
import auth_utils

router = APIRouter(prefix="/api/events", tags=["Events"])


def invalidate_event_list_cache(event: models.Event):
    event_day = event.event_time.date().isoformat()
    cache_keys = [
        f"events:{event.city}:{event.sport}:{event_day}",
        f"events:{event.city}:all:{event_day}",
        f"events:all:{event.sport}:{event_day}",
        f"events:all:all:{event_day}",
        f"events:{event.city}:{event.sport}:all",
        f"events:{event.city}:all:all",
        f"events:all:{event.sport}:all",
        "events:all:all:all",
    ]
    for cache_key in cache_keys:
        cache.delete_cached(cache_key)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def get_current_user(authorization: Optional[str] = Header(None)):
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Not authenticated")
    payload = auth_utils.decode_token(authorization[7:])
    if payload is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return payload


@router.get("")
def list_events(
    city: Optional[str] = None,
    sport: Optional[str] = None,
    day: Optional[str] = None,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    cache_key = f"events:{city or 'all'}:{sport or 'all'}:{day or 'all'}"

    cached = cache.get_cached(cache_key)
    if cached is not None:
        metrics.cache_hits.inc()
        return cached

    metrics.cache_misses.inc()

    query = db.query(models.Event)
    if city:
        query = query.filter(models.Event.city == city)
    if sport:
        query = query.filter(models.Event.sport == sport)
    if day:
        target = date.fromisoformat(day)
        day_start = datetime.combine(target, datetime.min.time())
        day_end = day_start + timedelta(days=1)
        query = query.filter(
            models.Event.event_time >= day_start,
            models.Event.event_time < day_end,
        )

    events = query.order_by(models.Event.event_time).all()
    result = [schemas.EventResponse.model_validate(e).model_dump(mode="json") for e in events]

    cache.set_cached(cache_key, result, ttl=30)
    return result


@router.post("", status_code=201)
def create_event(
    event_data: schemas.EventCreate,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    if user.get("role") != "organizer":
        raise HTTPException(status_code=403, detail="Only organizers can create events")

    new_event = models.Event(**event_data.model_dump())
    db.add(new_event)
    db.commit()
    db.refresh(new_event)

    invalidate_event_list_cache(new_event)

    return schemas.EventResponse.model_validate(new_event)


@router.post("/{event_id}/join")
def join_event(
    event_id: int,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    if user.get("role") != "player":
        raise HTTPException(status_code=403, detail="Only players can join events")

    event = (
        db.query(models.Event)
        .filter(models.Event.id == event_id)
        .with_for_update()
        .first()
    )
    if not event:
        raise HTTPException(status_code=404, detail="Event not found")

    already = db.query(models.EventParticipation).filter_by(
        user_id=user["user_id"], event_id=event_id
    ).first()
    if already:
        raise HTTPException(status_code=409, detail="Already joined this event")

    if event.joined_count >= event.capacity:
        raise HTTPException(status_code=409, detail="Event is full")

    try:
        db.add(models.EventParticipation(user_id=user["user_id"], event_id=event_id))
        event.joined_count += 1
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Already joined this event")
    db.refresh(event)

    invalidate_event_list_cache(event)

    return {"joined_count": event.joined_count, "capacity": event.capacity}
