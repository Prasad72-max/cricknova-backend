class CashfreeConfig {
  // DO NOT store Cashfree keys in Flutter app
  // These values must come from backend via API

  // Environment flag only (safe to keep)
  static const String env = "TEST";

  // Backend endpoint that creates Cashfree order
  static const String createOrderUrl =
      "https://YOUR_BACKEND_DOMAIN/payment/create-order";
}