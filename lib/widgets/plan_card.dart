import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config.dart';
import '../storekit/models.dart';
import '../team_subscription_controller.dart';

/// One plan with a seat picker, its price for that many seats, and the buy
/// button.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key, required this.controller, required this.plan});

  final TeamSubscriptionController controller;
  final TeamPlan plan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seats = controller.seatsFor(plan);
    final minSeats = controller.minSeatsFor(plan);
    final action = controller.actionFor(plan);
    final isBusy = controller.busyPlanId == plan.id;
    final money = NumberFormat.simpleCurrency(name: plan.currencyCode);
    final period = plan.periodLabel.isEmpty ? '' : ' / ${plan.periodLabel}';
    final canBuySeats =
        controller.sdkSupportsSeats && plan.supportsMultiSeatPurchase != false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plan.displayName, style: text.titleMedium),
            if (plan.description.isNotEmpty) Text(plan.description),
            const SizedBox(height: 8),
            Text('${plan.displayPrice} per seat$period'),
            for (final tier in plan.priceTiers)
              Text(
                '${tier.rangeLabel}: ${tier.displayPrice} per seat',
                style: text.bodySmall,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Seats'),
                const Spacer(),
                IconButton.outlined(
                  tooltip: 'Fewer seats',
                  onPressed:
                      action != PlanAction.scheduled &&
                          canBuySeats &&
                          seats > minSeats
                      ? () => controller.setSeats(plan, seats - 1)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    '$seats',
                    textAlign: TextAlign.center,
                    style: text.titleLarge,
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'More seats',
                  onPressed:
                      action != PlanAction.scheduled &&
                          canBuySeats &&
                          seats < maxSeats
                      ? () => controller.setSeats(plan, seats + 1)
                      : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${money.format(plan.totalFor(seats))}$period for $seats '
              '${seats == 1 ? 'seat' : 'seats'}',
              style: text.titleSmall,
            ),
            if (action == PlanAction.addSeats)
              Text(
                'You have ${controller.ownedSeats}. Pick the new total.',
                style: text.bodySmall,
              ),
            if (action == PlanAction.switchPlan)
              Text(
                'Your ${controller.ownedSeats} seats move to this plan.',
                style: text.bodySmall,
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    action == PlanAction.scheduled ||
                        controller.busyPlanId != null
                    ? null
                    : () => controller.buy(plan),
                child: isBusy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_label(action)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _label(PlanAction action) => switch (action) {
    PlanAction.subscribe => 'Subscribe',
    PlanAction.addSeats => 'Add seats',
    PlanAction.switchPlan => 'Switch plan',
    PlanAction.scheduled => 'Starts at renewal',
  };
}
