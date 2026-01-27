import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../premium/premium_screen.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  String? userEmail;

  File? profileImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString("profileName") ?? "Player";
    final imagePath = prefs.getString("profileImagePath");
    if (imagePath != null && imagePath.isNotEmpty) {
      profileImage = File(imagePath);
    }
    final user = FirebaseAuth.instance.currentUser;
    userEmail = user?.email;
    setState(() {});
  }

  Future<void> saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("profileName", nameController.text);
    if (profileImage != null) {
      await prefs.setString("profileImagePath", profileImage!.path);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Profile updated!")),
    );
  }


  Future<void> pickProfileImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        profileImage = File(picked.path);
      });
    }
  }

  void showPremiumPopup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PremiumScreen()),
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
      backgroundColor: const Color(0xFF0B0E11),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 🌌 SPACEFOCO PREMIUM HEADER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
              decoration: const BoxDecoration(
                color: Color(0xFF0F131A),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Stack(
                children: [
                  // Removed glowing circle Positioned widget for a cleaner look.
                  Column(
                    children: [
                      GestureDetector(
                        onTap: showImageOptions,
                        child: Container(
                          height: 110,
                          width: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF020617),
                            border: Border.all(color: Color(0xFF3B82F6), width: 1.5),
                          ),
                          child: ClipOval(
                            child: profileImage != null
                                ? Image.file(
                                    profileImage!,
                                    width: 110,
                                    height: 110,
                                    fit: BoxFit.cover,
                                  )
                                : const Icon(Icons.person, size: 70, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        "My Profile",
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          // Remove purple shadow for darker look
                        ),
                      ),
                      ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white70, Colors.white70],
                        ).createShader(bounds),
                        child: Text(
                          "Manage your cricket identity",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                      if (userEmail != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            userEmail!,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.white54,
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
                    style: const TextStyle(color: Colors.white),
                    decoration: inputStyle("Full Name"),
                  ),
                  const SizedBox(height: 15),
                  elevatedButton("Save Profile", saveName),
                ],
              ),
            ),

            const SizedBox(height: 20),


            const SizedBox(height: 20),

            // PREMIUM
            cardContainer(
              title: "Explore Premium",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspace_premium, color: Color(0xFFFFD700)),
                title: const Text("See all premium benefits", style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                onTap: showPremiumPopup,
              ),
            ),

            // LOG OUT
            cardContainer(
              title: "Account",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
                title: const Text("Log Out", style: TextStyle(color: Colors.white)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF3B82F6)),
                onTap: () async {
                  try {
                    // Firebase sign out
                    await FirebaseAuth.instance.signOut();

                    // Google sign out + disconnect to force account chooser
                    await _googleSignIn.signOut();
                    await _googleSignIn.disconnect();
                  } catch (_) {}

                  final prefs = await SharedPreferences.getInstance();
                  await prefs.clear();

                  if (!mounted) return;

                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
              ),
            ),

            const SizedBox(height: 20),


            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                "⚠️ AI Disclaimer:\nAll AI-generated insights, speed estimates, DRS decisions, and coaching feedback are provided for training and educational purposes only. Results may vary based on video quality, camera angle, lighting, and frame rate. CrickNova AI does not claim official match accuracy or replacement of professional umpires or coaches.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.white54,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 20),
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
          color: const Color(0xFF11151C),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white70)),
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
      fillColor: const Color(0xFF0F131A),
      labelStyle: const TextStyle(color: Colors.white70),
      floatingLabelStyle: const TextStyle(color: Colors.white),
      hintStyle: const TextStyle(color: Colors.white54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget elevatedButton(String text, Function onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF3B82F6),
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
      leading: Icon(icon, size: 28, color: const Color(0xFF3B82F6)),
      title: Text(text, style: const TextStyle(fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF3B82F6)),
      onTap: () => onTap(),
    );
  }
  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF3B82F6)),
                title: const Text("Upload from Gallery"),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? picked =
                      await _picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    setState(() {
                      profileImage = File(picked.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF3B82F6)),
                title: const Text("Open Camera"),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? picked =
                      await _picker.pickImage(source: ImageSource.camera);
                  if (picked != null) {
                    setState(() {
                      profileImage = File(picked.path);
                    });
                  }
                },
              ),
              if (profileImage != null)
                ListTile(
                  leading: const Icon(Icons.delete, color: Color(0xFFEF4444)),
                  title: const Text("Remove Profile Photo"),
                  onTap: () async {
                    Navigator.pop(context);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove("profileImagePath");
                    setState(() {
                      profileImage = null;
                    });
                  },
                ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }
}