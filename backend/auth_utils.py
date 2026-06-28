import bcrypt
from datetime import datetime, timedelta
from jose import jwt

# Security Configuration
SECRET_KEY = "gamba_super_secret_prototype_key"
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

def hash_password(password: str) -> str:
    """Takes a plain text password and returns a securely hashed version."""
    # Bcrypt requires bytes, so we encode the string first
    pwd_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed_bytes = bcrypt.hashpw(pwd_bytes, salt)
    
    # Decode back to a string so SQLAlchemy can save it in the database
    return hashed_bytes.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Checks if a provided password matches the hash stored in the DB."""
    plain_bytes = plain_password.encode('utf-8')
    hashed_bytes = hashed_password.encode('utf-8')
    
    return bcrypt.checkpw(plain_bytes, hashed_bytes)

def create_access_token(data: dict):
    """Creates a signed JSON Web Token (JWT) containing user info."""
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt