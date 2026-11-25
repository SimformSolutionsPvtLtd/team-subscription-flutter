import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../team_subscription_controller.dart';

/// What the account has now, from `Transaction.currentEntitlements`.
class CurrentPlanCard extends StatelessWidget {
  const CurrentPlanCard({super.key, required this.controller});

  final TeamSubscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final active = controller.active;

    if (active == null) {
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.lock_outline),
          title: const Text('No team plan yet'),
          subtitle: const Text(
            'Buy seats below, or accept an invitation from your team.',
          ),
        ),
      );
    }

    final plan = controller.planFor(active.productId);
    final scheduled = controller.planFor(active.scheduledPlanId);
    final expires = active.expirationDate;
    final renews = active.willAutoRenew ?? true;
    final isPurchaser = active.isPurchaser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan?.displayName ?? active.productId,
                    style: text.titleMedium,
                  ),
                ),
                Chip(label: Text(isPurchaser ? 'Purchaser' : 'Member')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isPurchaser
                  ? '${active.seats} ${active.seats == 1 ? 'seat' : 'seats'}'
                  : 'You have a seat in this group.',
              style: text.bodyLarge,
            ),
            if (expires != null)
              Text(
                '${renews ? 'Renews' : 'Ends'} '
                '${DateFormat.yMMMd().add_jm().format(expires)}',
              ),
            if (isPurchaser &&
                active.renewalSeats != null &&
                active.renewalSeats != active.seats)
              Text('${active.renewalSeats} seats from the next renewal'),
            if (scheduled != null)
              Text('Switches to ${scheduled.displayName} at renewal'),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: controller.manageSubscription,
              icon: const Icon(Icons.group_outlined),
              label: Text(isPurchaser ? 'Manage group' : 'Manage subscription'),
            ),
            if (isPurchaser)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Invite or remove members and reduce seats in Manage '
                  'group.',
                  style: text.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
