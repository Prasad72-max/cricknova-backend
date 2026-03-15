import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

enum ClaimRewardType {
  jersey,
  gloves,
  fullKit,
}

Future<void> showClaimFormSheet({
  required BuildContext context,
  required ClaimRewardType rewardType,
  String? sessionId,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ClaimFormSheet(
      rewardType: rewardType,
      sessionId: sessionId,
    ),
  );
}

class ClaimFormSheet extends StatefulWidget {
  const ClaimFormSheet({
    super.key,
    required this.rewardType,
    this.sessionId,
  });

  final ClaimRewardType rewardType;
  final String? sessionId;

  @override
  State<ClaimFormSheet> createState() => _ClaimFormSheetState();
}

class _ClaimFormSheetState extends State<ClaimFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _mobile = TextEditingController();
  final _customName = TextEditingController();
  final _handPref = ValueNotifier<String>("Right Hand");
  final _size = ValueNotifier<String>("Adult");
  final _jerseySize = ValueNotifier<String>("M");
  final _kitGift = ValueNotifier<String>("Bowling Machine Session Discount");
  final _helmetSize = ValueNotifier<String>("Adult");
  final _padSize = ValueNotifier<String>("Adult");
  final _screenshotUrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _mobile.dispose();
    _customName.dispose();
    _handPref.dispose();
    _size.dispose();
    _jerseySize.dispose();
    _kitGift.dispose();
    _helmetSize.dispose();
    _padSize.dispose();
    _screenshotUrl.dispose();
    super.dispose();
  }

  Color _headerColor() {
    switch (widget.rewardType) {
      case ClaimRewardType.jersey:
        return const Color(0xFFD4AF37); // Gold
      case ClaimRewardType.gloves:
        return const Color(0xFF38BDF8); // Blue
      case ClaimRewardType.fullKit:
        return const Color(0xFF22C55E); // Green
    }
  }

  String _title() {
    switch (widget.rewardType) {
      case ClaimRewardType.jersey:
        return "Official CrickNova Jersey";
      case ClaimRewardType.gloves:
        return "Batting Gloves + Special Gift";
      case ClaimRewardType.fullKit:
        return "Full Cricket Kit & English Willow Bat";
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to claim.")),
      );
      return;
    }

    setState(() => _submitting = true);
    final now = DateTime.now();
    final rewardKey = widget.rewardType.name;

    final doc = <String, dynamic>{
      "userId": user.uid,
      "email": user.email,
      "rewardType": rewardKey,
      "name": _name.text.trim(),
      "address": _address.text.trim(),
      "mobile": _mobile.text.trim(),
      "sessionId": widget.sessionId,
      "createdAt": now,
      "isClaimed": true,
    };

    if (widget.rewardType == ClaimRewardType.jersey) {
      doc["jerseySize"] = _jerseySize.value;
      doc["customName"] = _customName.text.trim();
    } else if (widget.rewardType == ClaimRewardType.gloves) {
      doc["handPreference"] = _handPref.value;
      doc["gloveSize"] = _size.value;
    } else if (widget.rewardType == ClaimRewardType.fullKit) {
      doc["screenshotUrl"] = _screenshotUrl.text.trim();
      doc["specialGiftChoice"] = _kitGift.value;
      doc["helmetSize"] = _helmetSize.value;
      doc["padSize"] = _padSize.value;
    }

    try {
      await FirebaseFirestore.instance.collection("claims").add(doc);
      await FirebaseFirestore.instance
          .collection("users")
          .doc(user.uid)
          .set({
        "claims": {rewardKey: true},
        "isClaimed": true,
      }, SetOptions(merge: true));

      // Trigger Cloud Function email
      try {
        await FirebaseFunctions.instance
            .httpsCallable("sendClaimEmail")
            .call(doc);
      } catch (_) {
        // Best-effort; ignore email errors for UX
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Claim submitted! We'll reach out soon."),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit: $e")),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerColor = _headerColor();
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      headerColor,
                      headerColor.withOpacity(0.7),
                    ],
                  ),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Claim Now",
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _title(),
                      style: GoogleFonts.poppins(
                        color: Colors.black.withOpacity(0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field("Name", _name),
                        _field("Mobile Number", _mobile,
                            keyboardType: TextInputType.phone),
                        _field("Address", _address, maxLines: 3),
                        if (widget.rewardType == ClaimRewardType.jersey) ...[
                          _dropdown("Jersey Size", _jerseySize, [
                            "S",
                            "M",
                            "L",
                            "XL",
                            "XXL",
                          ]),
                          _field(
                            "Custom Name (optional)",
                            _customName,
                            validator: (_) => null,
                          ),
                        ],
                        if (widget.rewardType == ClaimRewardType.gloves) ...[
                          _dropdown("Hand Preference", _handPref, [
                            "Left Hand",
                            "Right Hand",
                          ]),
                          _dropdown("Glove Size", _size, [
                            "Junior",
                            "Adult",
                            "Men",
                          ]),
                        ],
                        if (widget.rewardType == ClaimRewardType.fullKit) ...[
                          _field(
                            "Detailed Shipping Address (Home/Academy)",
                            _address,
                            maxLines: 3,
                          ),
                          _field(
                            "Profile Screenshot URL",
                            _screenshotUrl,
                            hint:
                                "Paste link to profile screenshot (for 2M+ XP verification)",
                          ),
                          _dropdown("Helmet Size", _helmetSize, [
                            "Junior",
                            "Adult",
                            "Men",
                          ]),
                          _dropdown("Pad Size", _padSize, [
                            "Junior",
                            "Adult",
                            "Men",
                          ]),
                          _dropdown("Special Gift Choice", _kitGift, [
                            "Bowling Machine Session Discount",
                            "Kit Bag",
                          ]),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: headerColor,
                              foregroundColor: Colors.black,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Text("Submit"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        validator: validator ??
            (value) {
              if (value == null || value.trim().isEmpty) {
                return "Required";
              }
              return null;
            },
      ),
    );
  }

  Widget _dropdown(
    String label,
    ValueNotifier<String> controller,
    List<String> options,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ValueListenableBuilder<String>(
        valueListenable: controller,
        builder: (_, value, __) => InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white70),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: const Color(0xFF0F172A),
              iconEnabledColor: Colors.white70,
              items: options
                  .map(
                    (o) => DropdownMenuItem(
                      value: o,
                      child: Text(
                        o,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) controller.value = v;
              },
            ),
          ),
        ),
      ),
    );
  }
}
