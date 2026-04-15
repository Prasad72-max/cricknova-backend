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

    if (!PremiumService.isLoaded) {
      await PremiumService.restoreOnLaunch();
    }

    final hasAccess =
        PremiumService.isPremiumActive &&
        allowedPlans.contains(PremiumService.plan);

    if (!hasAccess) {
      if (!context.mounted) return false;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PremiumScreen()),
      );
      return false;
    }

    return true;
  }
}
