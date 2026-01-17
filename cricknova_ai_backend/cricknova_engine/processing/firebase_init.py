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

def verify_firebase_token(id_token: str):
    """
    Verifies Firebase ID token sent from the client.
    Returns decoded token if valid, raises Exception otherwise.
    """
    if not id_token:
        raise ValueError("Missing Firebase ID token")

    try:
        decoded_token = auth.verify_id_token(id_token)
        return decoded_token
    except Exception as e:
        raise PermissionError(f"Invalid Firebase token: {str(e)}")