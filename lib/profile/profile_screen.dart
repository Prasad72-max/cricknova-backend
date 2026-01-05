import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../premium/premium_screen.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController dobController = TextEditingController();
  final TextEditingController battingRoleController = TextEditingController();
  final TextEditingController bowlingRoleController = TextEditingController();

  File? profileImage;
  final ImagePicker _picker = ImagePicker();

  final List<String> battingRoles = [
    "Right-hand Batsman",
    "Left-hand Batsman",
    "Right-hand All-rounder",
    "Left-hand All-rounder",
  ];

  final List<String> bowlingRoles = [
    "Right-arm Fast",
    "Right-arm Medium",
    "Right-arm Medium Pace",
    "Right-arm Off Spin",
    "Right-arm Leg Spin",
    "Left-arm Fast",
    "Left-arm Medium",
    "Left-arm Orthodox Spin",
    "Left-arm Chinaman",
  ];

  @override
  void initState() {
    super.initState();
    loadProfileData();
  }

  Future<void> loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    nameController.text = prefs.getString("profileName") ?? "Player";
    dobController.text = prefs.getString("profileDOB") ?? "";
    battingRoleController.text = prefs.getString("battingRole") ?? "";
    bowlingRoleController.text = prefs.getString("bowlingRole") ?? "";
    final imagePath = prefs.getString("profileImagePath");
    if (imagePath != null && imagePath.isNotEmpty) {
      profileImage = File(imagePath);
    }
    setState(() {});
  }

  Future<void> saveName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("profileName", nameController.text);
    await prefs.setString("profileDOB", dobController.text);
    await prefs.setString("battingRole", battingRoleController.text);
    await prefs.setString("bowlingRole", bowlingRoleController.text);
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
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Premium Features"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                ListTile(
                  leading: Icon(Icons.chat_bubble_outline, color: Colors.blue),
                  title: Text("AI Coach (Chat-based Coaching)"),
                ),
                ListTile(
                  leading: Icon(Icons.video_camera_back, color: Colors.green),
                  title: Text("AI Mistake Analysis (Video)"),
                ),
                ListTile(
                  leading: Icon(Icons.compare, color: Colors.orange),
                  title: Text("Diff / Video Compare Analysis"),
                ),
                ListTile(
                  leading: Icon(Icons.insights, color: Colors.purple),
                  title: Text("Advanced Cricket Insights with Limits"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                );
              },
              child: const Text(
                "Go Premium",
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          ],
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
                      GestureDetector(
                        onTap: showImageOptions,
                        child: Container(
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
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          shadows: const [
                            Shadow(
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
                            color: Theme.of(context).textTheme.bodySmall?.color,
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
                  const SizedBox(height: 12),
                  TextField(
                    controller: dobController,
                    decoration: inputStyle("Date of Birth (DD/MM/YYYY)"),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: battingRoleController.text.isNotEmpty
                        ? battingRoleController.text
                        : null,
                    items: battingRoles
                        .map((role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ))
                        .toList(),
                    onChanged: (value) {
                      battingRoleController.text = value ?? "";
                    },
                    decoration: inputStyle("Batting Role"),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: bowlingRoleController.text.isNotEmpty
                        ? bowlingRoleController.text
                        : null,
                    items: bowlingRoles
                        .map((role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ))
                        .toList(),
                    onChanged: (value) {
                      bowlingRoleController.text = value ?? "";
                    },
                    decoration: inputStyle("Bowling Role"),
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
                leading: const Icon(Icons.workspace_premium, color: Colors.amber),
                title: const Text("See all premium benefits"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                onTap: showPremiumPopup,
              ),
            ),

            // LOG OUT
            cardContainer(
              title: "Account",
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text("Log Out"),
                trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                onTap: () async {
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
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black54
                  : Colors.black12,
              blurRadius: 10,
            ),
          ],
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
      fillColor: Theme.of(context).brightness == Brightness.dark
          ? Colors.white10
          : Colors.grey[100],
      labelStyle: TextStyle(
        color: Theme.of(context).textTheme.bodyMedium?.color,
      ),
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
                leading: const Icon(Icons.photo_library),
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
                leading: const Icon(Icons.camera_alt),
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
                  leading: const Icon(Icons.delete, color: Colors.red),
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