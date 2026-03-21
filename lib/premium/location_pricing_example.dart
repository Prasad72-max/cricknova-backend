import 'package:flutter/material.dart';

import '../services/pricing_location_service.dart';

class LocationPricingExample extends StatefulWidget {
  const LocationPricingExample({super.key});

  @override
  State<LocationPricingExample> createState() => _LocationPricingExampleState();
}

class _LocationPricingExampleState extends State<LocationPricingExample> {
  PricingRegion _region = PricingRegion.global;
  bool _isDetecting = true;

  @override
  void initState() {
    super.initState();
    _loadPricingRegion();
  }

  Future<void> _loadPricingRegion() async {
    final region = await PricingLocationService.detectPricingRegion();
    if (!mounted) return;
    setState(() {
      _region = region;
      _isDetecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isIndia = _region == PricingRegion.india;

    return Scaffold(
      appBar: AppBar(title: const Text('Choose Plan')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isDetecting)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            Expanded(
              child: Center(
                child: isIndia
                    ? const _IndianPremiumPlanCard()
                    : const _GlobalPlanCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndianPremiumPlanCard extends StatelessWidget {
  const _IndianPremiumPlanCard();

  @override
  Widget build(BuildContext context) {
    return _PlanCard(
      title: 'Indian Premium Plan',
      price: 'INR 499 / month',
      color: const Color(0xFF0F766E),
    );
  }
}

class _GlobalPlanCard extends StatelessWidget {
  const _GlobalPlanCard();

  @override
  Widget build(BuildContext context) {
    return _PlanCard(
      title: 'Global Plan',
      price: 'USD 9.99 / month',
      color: const Color(0xFF1D4ED8),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title;
  final String price;
  final Color color;

  const _PlanCard({
    required this.title,
    required this.price,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            price,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Auto-renewing subscription. Cancel anytime.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
