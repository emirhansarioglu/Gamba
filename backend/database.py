from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Connection string matching docker-compose.dev.yml
SQLALCHEMY_DATABASE_URL = "postgresql://gamba:gamba@localhost:5432/gamba"

engine = create_engine(SQLALCHEMY_DATABASE_URL)

# Each request will get its own temporary session to query the database
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# All of our models will inherit from this Base class
Base = declarative_base()