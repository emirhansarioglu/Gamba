from pydantic import BaseModel, ConfigDict
from datetime import datetime


class UserRegister(BaseModel):
    username: str
    password: str
    role: str  # 'player' | 'organizer'


class UserLogin(BaseModel):
    username: str
    password: str


class EventCreate(BaseModel):
    city: str
    address: str
    sport: str
    level: int
    event_time: datetime
    capacity: int


class EventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    city: str
    address: str
    sport: str
    level: int
    event_time: datetime
    capacity: int
    joined_count: int
    created_at: datetime
