from sqlalchemy import Column, Integer, String, Text, DateTime, text
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    password = Column(String(255), nullable=False)
    role = Column(String(20), nullable=False)
    created_at = Column(DateTime, server_default=text('NOW()'))

class Event(Base):
    __tablename__ = "events"

    id = Column(Integer, primary_key=True, index=True)
    city = Column(String(100), nullable=False, index=True)
    address = Column(Text, nullable=False)
    sport = Column(String(50), nullable=False, index=True)
    level = Column(Integer, nullable=False)
    event_time = Column(DateTime, nullable=False)
    capacity = Column(Integer, nullable=False)
    joined_count = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, server_default=text('NOW()'))