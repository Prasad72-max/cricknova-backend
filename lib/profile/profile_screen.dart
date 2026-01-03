import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  bool darkMode = false;

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString("profileName") ?? "Player";
    darkMode = prefs.getBool("darkMode") ?? false;
    setState(() {});
  }

  Future<void> saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("profileName", nameController.text);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile updated!")),
    );
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("darkMode", darkMode);
  }

  void showPremiumPopup() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Premium Features"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              ListTile(
                leading: Icon(Icons.analytics, color: Colors.blue),
                title: Text("Advanced AI Batting Analysis"),
              ),
              ListTile(
                leading: Icon(Icons.speed, color: Colors.red),
                title: Text("Ball Speed Detection"),
              ),
              ListTile(
                leading: Icon(Icons.route, color: Colors.green),
                title: Text("Swing & Seam Movement Tracking"),
              ),
              ListTile(
                leading: Icon(Icons.sports_cricket, color: Colors.orange),
                title: Text("AI Shot Recommendations"),
              ),
            ],
          ),
        );
      },
    );
  }

  void logoutUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Logged out successfully")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🌌 SPACEFOCO PREMIUM HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
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
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent,
                    blurRadius: 40,
                    offset: Offset(0, 8),
                  )
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -20,
                    top: -15,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.blueAccent.withOpacity(0.7),
                            Colors.transparent
                          ],
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        height: 110,
                        width: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.7),
                              blurRadius: 25,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.person, size: 70, color: Colors.white),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "My Profile",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            const Shadow(
                              blurRadius: 18,
                              color: Colors.blueAccent,
                            ),
                          ],
                        ),
                      ),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white70, Colors.blueAccent],
                        ).createShader(bounds),
                        child: Text(
                          "Manage your cricket identity",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // PROFILE INFO
            cardContainer(
              title: "Profile Information",
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    decoration: inputStyle("Full Name"),
                  ),
                  const SizedBox(height: 15),
                  elevatedButton("Save Name", saveName),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // SETTINGS
            cardContainer(
              title: "Settings",
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Dark Theme"),
                value: darkMode,
                onChanged: (v) {
                  setState(() => darkMode = v);
                  saveSettings();
                },
              ),
            ),

            const SizedBox(height: 20),

            // PREMIUM
            cardContainer(
              title: "Explore Premium",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                title: const Text("See all premium benefits"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                onTap: showPremiumPopup,
              ),
            ),

            const SizedBox(height: 20),

            // AUTH
            cardContainer(
              title: "Authentication",
              child: Column(
                children: [
                  socialButton(Icons.phone, "Sign in with Phone", () {}),
                  socialButton(Icons.g_mobiledata, "Sign in with Google", () {}),
                  socialButton(Icons.apple, "Sign in with Apple ID", () {}),
                  socialButton(Icons.account_circle, "Sign in with Microsoft", () {}),
                  const SizedBox(height: 10),
                  elevatedButton("Log Out", logoutUser, color: Colors.red),
                ],
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // 📌 Helper Widgets
  Widget cardContainer({required String title, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  InputDecoration inputStyle(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget elevatedButton(String text, Function onTap, {Color color = Colors.blue}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () => onTap(),
        child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget socialButton(IconData icon, String text, Function onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 28),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => onTap(),
    );
  }
}