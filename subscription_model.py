

from datetime import datetime, timedelta


class Subscription:
    def __init__(self, user_id: str, plan_code: str):
        self.user_id = user_id
        self.plan_code = plan_code
        self.is_premium = True
        self.start_date = datetime.utcnow()
        self.end_date = self._calculate_end_date(plan_code)

    def _calculate_end_date(self, plan_code: str):
        if plan_code == "MONTHLY":
            return self.start_date + timedelta(days=30)
        elif plan_code == "SIX_MONTH":
            return self.start_date + timedelta(days=180)
        elif plan_code == "YEARLY":
            return self.start_date + timedelta(days=365)
        elif plan_code == "ULTRA":
            return self.start_date + timedelta(days=365)
        else:
            return self.start_date

    def is_active(self):
        return datetime.utcnow() <= self.end_date

    def to_dict(self):
        return {
            "user_id": self.user_id,
            "plan_code": self.plan_code,
            "is_premium": self.is_premium,
            "start_date": self.start_date.isoformat(),
            "end_date": self.end_date.isoformat(),
        }

    @staticmethod
    def from_dict(data: dict):
        sub = Subscription(data["user_id"], data["plan_code"])
        sub.is_premium = data.get("is_premium", False)
        sub.start_date = datetime.fromisoformat(data["start_date"])
        sub.end_date = datetime.fromisoformat(data["end_date"])
        return sub