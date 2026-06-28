from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import socket
from database import engine
import models
from routers import auth

# Create the tables if they don't exist yet
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Gamba API")

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