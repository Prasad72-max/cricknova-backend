

from fastapi import Header, HTTPException, status
from cricknova_engine.processing.firebase_init import verify_firebase_token


def get_current_user(authorization: str = Header(None)):
    """
    FastAPI dependency to extract and verify Firebase user from Authorization header.
    Expects: Authorization: Bearer <FIREBASE_ID_TOKEN>
    """
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="USER_NOT_AUTHENTICATED",
        )

    try:
        uid = verify_firebase_token(authorization)
        return {"uid": uid}
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="USER_NOT_AUTHENTICATED",
        )