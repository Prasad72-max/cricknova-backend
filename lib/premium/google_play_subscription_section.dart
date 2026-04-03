import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/subscription_provider.dart';

class GooglePlaySubscriptionSection extends StatelessWidget {
  const GooglePlaySubscriptionSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionProvider>(
      builder: (BuildContext context, SubscriptionProvider provider, _) {
        final ThemeData theme = Theme.of(context);

        if (provider.isLoading && provider.plans.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (provider.lastError != null) ...<Widget>[
              _StatusBanner(
                message: provider.lastError!,
                backgroundColor: const Color(0xFFFFF1F0),
                foregroundColor: const Color(0xFFB42318),
              ),
              const SizedBox(height: 12),
            ],
            if (provider.isPremium) ...<Widget>[
              _StatusBanner(
                message:
                    'Premium active on ${provider.activeBasePlanId ?? '-'} until '
                    '${provider.expiryDate?.toLocal().toString() ?? '-'} '
                    '• AI used ${provider.aiUsed}/${provider.aiLimit}',
                backgroundColor: const Color(0xFFE8FFF3),
                foregroundColor: const Color(0xFF027A48),
              ),
              const SizedBox(height: 16),
            ],
            Text(
              'Google Play Plans',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fetched from product: ${SubscriptionProvider.premiumProductId}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ...provider.plans.map(
              (GooglePlaySubscriptionPlan plan) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PlanCard(plan: plan),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: provider.isPurchasePending
                        ? null
                        : provider.restorePurchases,
                    child: const Text('Restore Purchases'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: provider.isLoading
                        ? null
                        : provider.fetchProducts,
                    child: const Text('Refresh Plans'),
                  ),
                ),
              ],
            ),
            if (provider.isPurchasePending) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan});

  final GooglePlaySubscriptionPlan plan;

  @override
  Widget build(BuildContext context) {
    final SubscriptionProvider provider = context.read<SubscriptionProvider>();
    final bool isActive = provider.activeBasePlanId == plan.basePlanId;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    plan.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8FFF3),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        color: Color(0xFF027A48),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan.displayPrice,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('Base plan: ${plan.basePlanId}'),
            const SizedBox(height: 4),
            Text('AI limit: ${plan.aiLimit}'),
            const SizedBox(height: 4),
            Text(plan.description),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: provider.isPurchasePending
                    ? null
                    : () => provider.purchasePlan(plan),
                child: Text(
                  isActive ? 'Subscribed' : 'Subscribe with Google Play',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String message;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: foregroundColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
