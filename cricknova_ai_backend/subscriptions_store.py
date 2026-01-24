# -----------------------------
# USAGE COUNTERS
# -----------------------------
def increment_chat(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "chat")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("CHAT_LIMIT_EXCEEDED")
    return True


def increment_mistake(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "mistake")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("MISTAKE_LIMIT_EXCEEDED")
    return True


def increment_compare(user_id: str):
    ok, premium_required = check_limit_and_increment(user_id, "compare")
    if not ok:
        if premium_required:
            raise ValueError("PREMIUM_REQUIRED")
        raise ValueError("COMPARE_LIMIT_EXCEEDED")
    return True