import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../theme/crickx_colors.dart';

class EditProfileScreen extends StatefulWidget {
  final String name;
  final String email;
  final String profilePic;

  const EditProfileScreen({
    super.key,
    required this.name,
    required this.email,
    required this.profilePic,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController nameController;
  late TextEditingController emailController;

  String? imagePath;
  late String profileImage;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.name);
    emailController = TextEditingController(text: widget.email);
    profileImage = widget.profilePic;
  }

  Future<void> pickImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: CrickXColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SizedBox(
        height: 160,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white),
              title: Text("Choose from Gallery",
                  style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? img =
                    await picker.pickImage(source: ImageSource.gallery);
                if (img != null) {
                  setState(() => imagePath = img.path);
                }
              },
            ),

            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.white),
              title:
                  Text("Take Photo", style: GoogleFonts.poppins(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? img =
                    await picker.pickImage(source: ImageSource.camera);
                if (img != null) {
                  setState(() => imagePath = img.path);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CrickXColors.graphiteBg,

      appBar: AppBar(
        backgroundColor: CrickXColors.graphiteBg,
        title:
            Text("Edit Profile", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            InkWell(
              onTap: pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: CrickXColors.graphiteElevated,
                backgroundImage: imagePath != null
                    ? FileImage(File(imagePath!))
                    : profileImage.contains("http")
                        ? NetworkImage(profileImage)
                        : (profileImage.isNotEmpty && File(profileImage).existsSync()
                            ? FileImage(File(profileImage)) as ImageProvider
                            : null),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: CrickXColors.limeSpark,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit,
                        color: CrickXColors.onLime, size: 18),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 25),

            TextField(
              controller: nameController,
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: _input("Name"),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: emailController,
              style: GoogleFonts.poppins(color: Colors.white),
              decoration: _input("Email"),
            ),

            const Spacer(),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, {
                  "name": nameController.text,
                  "email": emailController.text,
                  "profilePic": imagePath ?? profileImage,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CrickXColors.limeSpark,
                foregroundColor: CrickXColors.onLime,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text("Save",
                  style: GoogleFonts.poppins(color: CrickXColors.onLime, fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _input(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: CrickXColors.graphiteBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: CrickXColors.limeSpark),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
