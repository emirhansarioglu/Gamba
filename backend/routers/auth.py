from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from database import SessionLocal
import models
import auth_utils

router = APIRouter(prefix="/api/auth", tags=["Authentication"])

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@router.post("/register", status_code=status.HTTP_201_CREATED)
def register_user(user_data: dict, db: Session = Depends(get_db)):
    """Creates a new user in the database."""
    
    # 1. Check if username already exists
    existing_user = db.query(models.User).filter(models.User.username == user_data["username"]).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")
    # 2. Hash the password
    hashed_pw = auth_utils.hash_password(user_data["password"])
    # 3. Save to database
    new_user = models.User(
        username=user_data["username"],
        password=hashed_pw,
        role=user_data["role"]
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    # 4. Return success (but never return the password!)
    return {"username": new_user.username, "role": new_user.role}

@router.post("/login")
def login_user(credentials: dict, db: Session = Depends(get_db)):
    """Verifies credentials and returns a JWT."""
    
    # 1. Find user in database
    user = db.query(models.User).filter(models.User.username == credentials["username"]).first()
    
    # 2. Verify existence and password
    if not user or not auth_utils.verify_password(credentials["password"], user.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    # 3. Create the JWT token
    token_data = {"user_id": user.id, "username": user.username, "role": user.role}
    access_token = auth_utils.create_access_token(data=token_data)
    
    # 4. Return the token to the frontend
    return {"access_token": access_token, "role": user.role}