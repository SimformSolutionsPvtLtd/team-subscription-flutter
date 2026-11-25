import 'models.dart';

/// The seat rules from the article, as plain functions with no StoreKit or
/// Flutter dependency, so they're easy to unit test.

/// Which subscription to show when the account has several entitlements, for
/// example a seat at work and their own group at home. Shows what they can
/// manage: their PURCHASED transaction first, then their own ASSIGNED copy
/// (the purchaser can look like a member), then someone else's group.
///
/// Pass the entitlements for every plan in ONE subscription group (for
/// example Monthly and Yearly), not just the product being bought: seats
/// belong to the group, and on a plan switch the active entitlement is on
/// the other plan.
SubscriptionEntitlement? pickActiveSubscription(
  Iterable<SubscriptionEntitlement> entitlements,
) {
  int rank(SubscriptionEntitlement e) => !e.isPurchaser
      ? 2
      : e.ownershipType == 'PURCHASED'
      ? 0
      : 1;
  if (entitlements.isEmpty) return null;
  return entitlements.reduce((best, e) => rank(e) < rank(best) ? e : best);
}

/// The seats the purchaser already has in the subscription group, or 0 if
/// this account isn't the purchaser. Seats belong to the group, so they carry
/// over when the group switches plans.
int groupSeats(SubscriptionEntitlement? active) =>
    active != null && active.isPurchaser ? active.seats : 0;

/// The lowest total the seat picker offers for [productId], which is also
/// where it starts. `seats(_:)` takes the total after the purchase, so on the
/// current plan it's one above the seats owned, and on another plan in the
/// group (a plan switch) it's the current seats.
int initialSeats(String productId, SubscriptionEntitlement? active) {
  final owned = groupSeats(active);
  if (owned == 0) return 1;
  return active!.productId == productId ? owned + 1 : owned;
}

/// Whether buying [seats] of [productId] would lower the seat count, which
/// StoreKit rejects with `seatReductionNotAllowed`. Reductions happen in
/// Manage Subscriptions, at the next renewal.
bool isSeatReduction(
  String productId,
  int seats,
  SubscriptionEntitlement? active,
) {
  final owned = groupSeats(active);
  if (owned == 0) return false;
  final isPlanSwitch = active!.productId != productId;
  return isPlanSwitch ? seats < owned : seats <= owned;
}

/// Whether a `purchased` result is an older, unfinished transaction rather
/// than the one just bought. A real purchase is always PURCHASED and dated
/// around [startedAt].
bool isStalePurchaseResult(Map<Object?, Object?> result, DateTime startedAt) {
  if (result['ownershipType'] != 'PURCHASED') return true;
  final purchaseDate = result['purchaseDate'];
  if (purchaseDate is! num) return false;
  return DateTime.fromMillisecondsSinceEpoch(
    purchaseDate.toInt(),
  ).isBefore(startedAt.subtract(const Duration(minutes: 2)));
}

/// Whether StoreKit returned the current plan's transaction for a purchase
/// of [productId]: a downgrade, scheduled for the next renewal.
bool isScheduledDowngrade(Map<Object?, Object?> result, String productId) =>
    result['status'] == 'purchased' &&
    result['productId'] != null &&
    result['productId'] != productId;
