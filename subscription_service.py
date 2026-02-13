

from datetime import datetime
from subscription_model import Subscription

# Temporary in-memory store (Replace with DB later)
SUBSCRIPTION_STORE = {}


def activate_subscription(user_id: str, plan_code: str):
    """
    Activate premium subscription for a user after successful payment.
    """
    subscription = Subscription(user_id, plan_code)
    SUBSCRIPTION_STORE[user_id] = subscription.to_dict()
    return subscription.to_dict()


def get_subscription(user_id: str):
    """
    Retrieve user subscription data.
    """
    data = SUBSCRIPTION_STORE.get(user_id)
    if not data:
        return None
    return Subscription.from_dict(data)


def check_and_update_expiry(user_id: str):
    """
    Check if subscription expired and update status.
    """
    subscription = get_subscription(user_id)

    if not subscription:
        return False

    if datetime.utcnow() > subscription.end_date:
        subscription.is_premium = False
        SUBSCRIPTION_STORE[user_id] = subscription.to_dict()
        return False

    return True


def is_user_premium(user_id: str):
    """
    Returns True if user has active premium.
    """
    subscription = get_subscription(user_id)
    if not subscription:
        return False

    return subscription.is_active()