

from subscription_service import check_and_update_expiry, is_user_premium
from fastapi import HTTPException


def enforce_premium(user_id: str):
    """
    Call this before allowing access to any premium feature.
    Automatically disables expired users.
    """

    # Update expiry status first
    active = check_and_update_expiry(user_id)

    if not active:
        raise HTTPException(
            status_code=403,
            detail="Premium expired or not active. Please renew your plan."
        )

    # Final validation
    if not is_user_premium(user_id):
        raise HTTPException(
            status_code=403,
            detail="Premium access required."
        )

    return True