import 'package:flutter/material.dart';
import '../services/premium_service.dart';
import '../premium/premium_screen.dart';

Future<bool> checkPremiumAndRedirect(BuildContext context) async {
  final isPremium = await PremiumService.isPremium();

  if (!isPremium) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PremiumScreen()),
    );
    return false;
  }

  return true;
}