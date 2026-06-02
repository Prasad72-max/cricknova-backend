import firebase_admin
from firebase_admin import credentials, firestore, auth
import os

_MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
_PACKAGE_ROOT = os.path.abspath(os.path.join(_MODULE_DIR, "..", "..", ".."))

def _resolve_credential_path(path: str | None):
    if not path:
        return None
    if os.path.isabs(path) and os.path.exists(path):
        return path
    for root in (os.getcwd(), _MODULE_DIR, _PACKAGE_ROOT):
        candidate = os.path.join(root, path)
        if os.path.exists(candidate):
            return candidate
    return path if os.path.exists(path) else None

def _ensure_initialized():
    if firebase_admin._apps:
        return

    cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "firebase_key.json")
    resolved_cred_path = _resolve_credential_path(cred_path)
    if not resolved_cred_path:
        raise RuntimeError(f"Firebase credentials not found at {cred_path}")

    cred = credentials.Certificate(resolved_cred_path)
    firebase_admin.initialize_app(cred)


def get_db():
    _ensure_initialized()
    return firestore.client()

def verify_firebase_token(id_token: str):
    """
    Verifies Firebase ID token sent from the client.
    Returns decoded token if valid, raises Exception otherwise.
    """
    if not id_token:
        raise ValueError("Missing Firebase ID token")

    try:
        _ensure_initialized()
        decoded_token = auth.verify_id_token(id_token)
        return decoded_token
    except Exception as e:
        raise PermissionError(f"Invalid Firebase token: {str(e)}")
