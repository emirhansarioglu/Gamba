from fastapi import FastAPI
import socket
from database import engine
import models

# Create the tables if they don't exist yet
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Gamba API")

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