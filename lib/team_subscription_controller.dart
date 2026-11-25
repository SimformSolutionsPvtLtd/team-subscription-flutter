import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'storekit/models.dart';
import 'storekit/seat_rules.dart';
import 'storekit/storekit_bridge.dart';

/// What the buy button does for a plan.
enum PlanAction {
  /// No group yet: start one (or a single-person subscription).
  subscribe,

  /// The group's current plan: raise the total number of seats.
  addSeats,

  /// Another plan in the group: move the group, and its seats, to it.
  switchPlan,

  /// A downgrade to this plan already starts at the next renewal.
  scheduled,
}

/// App state for the team plans screen.
class TeamSubscriptionController extends ChangeNotifier {
  TeamSubscriptionController({
    required this.bridge,
    List<String>? planIds,
    DateTime Function()? clock,
  }) : planIds = planIds ?? teamPlanIds,
       _clock = clock ?? DateTime.now;

  /// The native StoreKit 2 bridge (a fake in tests).
  final StoreKitBridge bridge;
  final DateTime Function() _clock;
  final List<String> planIds;

  bool isLoading = true;
  String? loadError;
  bool sdkSupportsSeats = false;
  List<TeamPlan> plans = const [];

  /// The subscription the app shows and grants access from.
  SubscriptionEntitlement? active;

  /// The plan whose purchase is in progress.
  String? busyPlanId;

  final _selectedSeats = <String, int>{};
  final _messages = StreamController<String>.broadcast();

  /// One-off messages for the user, such as purchase results.
  Stream<String> get messages => _messages.stream;

  bool get hasAccess => active != null;

  /// Seats the purchaser has in the group, or 0 (no group, or a member).
  int get ownedSeats => groupSeats(active);

  TeamPlan? planFor(String? productId) =>
      plans.where((p) => p.id == productId).firstOrNull;

  Future<void> start() async {
    bridge.onTransactionsUpdated = () => unawaited(refreshEntitlements());
    await load();
  }

  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      final catalog = await bridge.loadProducts(planIds);
      sdkSupportsSeats = catalog.sdkSupportsSeats;
      // Keep the order from config.dart; StoreKit returns its own order.
      plans = [
        for (final id in planIds)
          ?catalog.plans.where((p) => p.id == id).firstOrNull,
      ];
      await _readEntitlements();
    } on PlatformException catch (e) {
      loadError = e.message ?? e.code;
    }
    isLoading = false;
    notifyListeners();
  }

  /// Re-reads `Transaction.currentEntitlements`. Call it at launch, after a
  /// purchase, after restore and when Manage Subscriptions closes; a revoked
  /// or removed seat disappears on the next read.
  Future<void> refreshEntitlements() async {
    try {
      await _readEntitlements();
    } on PlatformException catch (e) {
      _messages.add(e.message ?? e.code);
    }
    notifyListeners();
  }

  Future<void> _readEntitlements() async {
    final entitlements = await bridge.currentEntitlements();
    debugPrint(
      '[team] entitlements: ${entitlements.map((e) => '${e.productId} '
          'seats=${e.seats} ${e.ownershipType} role=${e.groupRole} '
          'renewsTo=${e.renewsToProductId}').toList()}',
    );
    // Every plan in the group, not just one product: seats belong to the
    // group and move with it when it switches plans.
    active = pickActiveSubscription(
      entitlements.where((e) => planIds.contains(e.productId)),
    );
    _selectedSeats.clear();
  }

  // MARK: Seat picker

  int minSeatsFor(TeamPlan plan) => initialSeats(plan.id, active);

  int seatsFor(TeamPlan plan) =>
      _selectedSeats[plan.id] ?? initialSeats(plan.id, active);

  void setSeats(TeamPlan plan, int seats) {
    final min = minSeatsFor(plan);
    _selectedSeats[plan.id] = seats.clamp(min, maxSeats < min ? min : maxSeats);
    notifyListeners();
  }

  PlanAction actionFor(TeamPlan plan) {
    if (active?.scheduledPlanId == plan.id) return PlanAction.scheduled;
    if (ownedSeats == 0) return PlanAction.subscribe;
    return active!.productId == plan.id
        ? PlanAction.addSeats
        : PlanAction.switchPlan;
  }

  // MARK: Actions

  Future<void> buy(TeamPlan plan) async {
    if (busyPlanId != null || actionFor(plan) == PlanAction.scheduled) return;
    final seats = seatsFor(plan);
    if (isSeatReduction(plan.id, seats, active)) {
      _messages.add(
        'You have $ownedSeats seats. Pick more, or reduce seats in Manage '
        'subscription.',
      );
      return;
    }
    // One seat with no group is an ordinary subscription. Anything else needs
    // seats(_:), with the total after the purchase. A plan switch sends the
    // group's current total, so its seats move to the new plan.
    final isTeamPurchase = seats > 1 || ownedSeats > 0;

    busyPlanId = plan.id;
    notifyListeners();
    final startedAt = _clock();
    try {
      final result = await bridge.purchase(
        plan.id,
        seats: isTeamPurchase ? seats : null,
      );
      debugPrint(
        '[team] purchase ${plan.id} seats=${isTeamPurchase ? seats : null}: '
        '${result['status']} product=${result['productId']} '
        'quantity=${result['purchasedQuantity']} '
        'ownership=${result['ownershipType']}',
      );
      _messages.add(_describe(result, plan, seats, startedAt));
    } on PlatformException catch (e) {
      debugPrint('[team] purchase ${plan.id} failed: ${e.code} ${e.message}');
      _messages.add(_errorMessage(e));
    } finally {
      busyPlanId = null;
    }
    // Access comes from entitlements, never from the purchase result.
    await refreshEntitlements();
  }

  String _describe(
    Map<Object?, Object?> result,
    TeamPlan plan,
    int seats,
    DateTime startedAt,
  ) {
    switch (result['status']) {
      case 'cancelled':
        return 'Purchase cancelled.';
      case 'pending':
        return 'Purchase pending approval. You get access once it goes '
            'through.';
      case 'purchased':
        if (isScheduledDowngrade(result, plan.id)) {
          return '${plan.displayName} starts at your next renewal.';
        }
        if (isStalePurchaseResult(result, startedAt)) {
          return 'StoreKit returned an earlier purchase. It is finished now, '
              'so tap again to buy.';
        }
        return seats > 1
            ? 'Your team now has $seats seats on ${plan.displayName}.'
            : 'Subscribed to ${plan.displayName}.';
      default:
        return 'The purchase did not complete.';
    }
  }

  String _errorMessage(PlatformException e) => switch (e.code) {
    'SEAT_REDUCTION_NOT_ALLOWED' ||
    'MULTI_SEAT_PURCHASE_DISABLED' ||
    'SDK_TOO_OLD' => e.message ?? e.code,
    'PRODUCT_NOT_FOUND' => 'Product ${e.message} is not on the App Store.',
    _ => 'Purchase failed: ${e.message ?? e.code}',
  };

  Future<void> restorePurchases() async {
    try {
      await bridge.restorePurchases();
      await refreshEntitlements();
      _messages.add(
        hasAccess ? 'Purchases restored.' : 'No active team plan found.',
      );
    } on PlatformException catch (e) {
      _messages.add('Restore failed: ${e.message ?? e.code}');
    }
  }

  Future<void> manageSubscription() async {
    try {
      await bridge.showManageSubscriptions();
    } on PlatformException catch (e) {
      _messages.add(e.message ?? e.code);
    }
    // Members or seats may have changed in the sheet.
    await refreshEntitlements();
  }

  @override
  void dispose() {
    bridge.onTransactionsUpdated = null;
    unawaited(_messages.close());
    super.dispose();
  }
}
