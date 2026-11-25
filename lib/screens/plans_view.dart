import 'package:flutter/material.dart';

import '../team_subscription_controller.dart';
import '../widgets/current_plan_card.dart';
import '../widgets/notice.dart';
import '../widgets/plan_card.dart';

/// The team plans tab: what the account has now, and the plans with a seat
/// picker.
class PlansView extends StatelessWidget {
  const PlansView({super.key, required this.controller});

  final TeamSubscriptionController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _body(context, controller),
  );

  Widget _body(BuildContext context, TeamSubscriptionController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = controller.loadError;
    if (error != null) {
      return Notice(
        icon: Icons.cloud_off,
        title: "Couldn't load plans",
        body: error,
        action: FilledButton(
          onPressed: controller.load,
          child: const Text('Try again'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.refreshEntitlements,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!controller.sdkSupportsSeats) ...[
            const _SdkBanner(),
            const SizedBox(height: 16),
          ],
          CurrentPlanCard(controller: controller),
          const SizedBox(height: 24),
          Text('Plans', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'One person buys seats and invites the team. Everyone gets '
            'access on their own Apple Account.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (controller.plans.isEmpty)
            const Notice(
              icon: Icons.inventory_2_outlined,
              title: 'No plans found',
              body:
                  'StoreKit returned none of the TEAM_PLAN_IDS in '
                  'config.json. Run with --dart-define-from-file=config.json, '
                  'and check the IDs against App Store Connect.',
            ),
          for (final plan in controller.plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PlanCard(controller: controller, plan: plan),
            ),
        ],
      ),
    );
  }
}

class _SdkBanner extends StatelessWidget {
  const _SdkBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'This build can only sell single-person subscriptions. Build with '
          'Xcode 27.3 or later and the MULTISEAT_SDK compilation condition to '
          'buy seats.',
          style: TextStyle(color: colors.onErrorContainer),
        ),
      ),
    );
  }
}
