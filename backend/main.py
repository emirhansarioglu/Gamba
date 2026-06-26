from fastapi import FastAPI
import socket

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