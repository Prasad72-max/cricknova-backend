import firebase_admin
from firebase_admin import credentials, firestore, auth
import os

# Initialize Firebase only once
if not firebase_admin._apps:
    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "firebase_key.json")
    if not os.path.exists(cred_path):
        raise RuntimeError(f"Firebase credentials not found at {cred_path}")

    cred = credentials.Certificate(cred_path)
    firebase_admin.initialize_app(cred)

# Firestore client
db = firestore.client()

def verify_firebase_token(auth_header: str):
    """
    Verifies Firebase ID token.
    Accepts:
    - 'Bearer <firebase_id_token>'
    - '<firebase_id_token>' (Swagger / quick tests)
    Returns: uid (str)
    """
    if not auth_header:
        raise PermissionError("Authorization header missing")

    # Accept both formats
    if auth_header.startswith("Bearer "):
        id_token = auth_header.split(" ", 1)[1].strip()
    else:
        id_token = auth_header.strip()

    # Basic sanity check
    if id_token.count(".") != 2:
        raise PermissionError("Malformed Firebase token")

    try:
        decoded_token = auth.verify_id_token(id_token)
        return decoded_token.get("uid")
    except Exception as e:
        raise PermissionError(f"Invalid Firebase token: {str(e)}")