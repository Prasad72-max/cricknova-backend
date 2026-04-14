import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';

class PremiumGuard {
  static Future<bool> ensureAccess({
    required BuildContext context,
    required List<String> allowedPlans,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final hasAccess =
        await PremiumService.hasValidPlan(allowedPlans);

    if (!hasAccess) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PremiumScreen(),
        ),
      );
      return false;
    }

    return true;
  }
}