

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'premium_screen.dart';
import '../services/premium_service.dart';

class PremiumExpiredScreen extends StatelessWidget {
  const PremiumExpiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.workspace_premium,
                size: 80,
                color: Color(0xFFFFD700),
              ),
              const SizedBox(height: 24),
              Text(
                "Your Elite Plan Has Ended",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Thank you for being a premium member.\n\nRenew your plan to continue enjoying AI analysis and advanced features.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.white70,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                "Plan Period",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                "Started: ${PremiumService.startedDate?.toLocal().toString() ?? "-"}",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "Ended: ${PremiumService.expiryDate?.toLocal().toString() ?? "-"}",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.redAccent,
                ),
              ),

              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const PremiumScreen(entrySource: "expired"),
                    ),
                  );
                },
                child: const Text(
                  "Renew Now",
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  "Maybe Later",
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}