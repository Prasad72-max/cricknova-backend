import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../home/home_screen.dart';
import '../ai/ai_coach_screen.dart';
import '../premium/premium_screen.dart';
import '../profile/profile_screen.dart';
import '../services/premium_service.dart';

class MainNavigation extends StatefulWidget {
  final String userName;

  const MainNavigation({super.key, required this.userName});

  static _MainNavigationState? of(BuildContext context) {
    return context.findAncestorStateOfType<_MainNavigationState>();
  }

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = 0;
  String userName = "Player";

  void goHome() {
    if (_index != 0) {
      setState(() {
        _index = 0;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadUser();

    // 🔁 Always sync premium & usage from backend on app start / relogin
    Future.microtask(() async {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await PremiumService.syncFromBackend(user.uid);
        }
      } catch (e) {
        debugPrint("Premium sync failed: $e");
      }
    });
  }

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString("profileName") ?? widget.userName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(userName: userName),
      const AICoachScreen(),
      const PremiumScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      appBar: _index == 0
          ? null
          : AppBar(
              backgroundColor: (_index == 1 || _index == 2)
                  ? Colors.black
                  : Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: (_index == 1 || _index == 2)
                  ? null
                  : Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0xFF050A1E),
                            Color(0xFF0E1A36),
                            Color(0xFF1E3A8A),
                            Color(0xFF3B82F6),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: goHome,
              ),
              iconTheme: const IconThemeData(color: Colors.white),
              title: const Text(
                "CrickNova AI",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              centerTitle: true,
            ),
      body: screens[_index],

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.white70,
        type: BottomNavigationBarType.fixed,

        onTap: (i) {
          // AI Coach tab index = 1
          if (i == 1 && !PremiumService.isPremium) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "AI Coach is a Premium feature. Upgrade to unlock AI coaching.",
                ),
                duration: Duration(seconds: 2),
              ),
            );

            setState(() {
              _index = 2; // Premium tab
            });
            return;
          }

          setState(() {
            _index = i;
          });
        },

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: "AI Coach"),
          BottomNavigationBarItem(icon: Icon(Icons.workspace_premium), label: "Premium"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}