/// One per-seat price that applies to a range of seats
/// (`Product.SubscriptionInfo.PricingTerms.SeatBasedPricing.PriceTier`).
class SeatPriceTier {
  const SeatPriceTier({
    required this.minimumSeats,
    required this.maximumSeats,
    required this.price,
    required this.displayPrice,
  });

  factory SeatPriceTier.fromMap(Map<Object?, Object?> map) => SeatPriceTier(
    minimumSeats: (map['minimumSeats'] as num).toInt(),
    maximumSeats: (map['maximumSeats'] as num?)?.toInt(),
    price: (map['price'] as num).toDouble(),
    displayPrice: map['displayPrice'] as String? ?? '',
  );

  final int minimumSeats;

  /// `null` for the last tier, which has no upper limit.
  final int? maximumSeats;

  /// Price of one seat in this tier.
  final double price;
  final String displayPrice;

  String get rangeLabel => maximumSeats == null
      ? '$minimumSeats+ seats'
      : '$minimumSeats–$maximumSeats seats';
}

/// An auto-renewable subscription that can be bought for a team.
class TeamPlan {
  const TeamPlan({
    required this.id,
    required this.displayName,
    required this.description,
    required this.displayPrice,
    required this.price,
    required this.currencyCode,
    this.subscriptionGroupId,
    this.periodUnit,
    this.periodValue,
    this.supportsMultiSeatPurchase,
    this.priceTiers = const [],
  });

  factory TeamPlan.fromMap(Map<Object?, Object?> map) => TeamPlan(
    id: map['id'] as String,
    displayName: map['displayName'] as String? ?? '',
    description: map['description'] as String? ?? '',
    displayPrice: map['displayPrice'] as String? ?? '',
    price: (map['price'] as num?)?.toDouble() ?? 0,
    currencyCode: map['currencyCode'] as String? ?? 'USD',
    subscriptionGroupId: map['subscriptionGroupId'] as String?,
    periodUnit: map['periodUnit'] as String?,
    periodValue: (map['periodValue'] as num?)?.toInt(),
    supportsMultiSeatPurchase: map['supportsMultiSeatPurchase'] as bool?,
    priceTiers: (map['priceTiers'] as List<Object?>? ?? const [])
        .map((e) => SeatPriceTier.fromMap(e! as Map<Object?, Object?>))
        .toList(),
  );

  final String id;
  final String displayName;
  final String description;

  /// Price of one seat (or one person), formatted by StoreKit.
  final String displayPrice;
  final double price;
  final String currencyCode;
  final String? subscriptionGroupId;

  /// `day`, `week`, `month` or `year`.
  final String? periodUnit;
  final int? periodValue;

  /// `Product.supportsMultiSeatPurchase`; `null` below iOS 27.3, where
  /// StoreKit can't report it.
  final bool? supportsMultiSeatPurchase;

  /// Volume-discount tiers. Empty below iOS 27.3, or when every seat costs
  /// the same ([price]).
  final List<SeatPriceTier> priceTiers;

  /// "month", "year", "3 months"...
  String get periodLabel {
    final unit = periodUnit;
    final value = periodValue ?? 1;
    if (unit == null) return '';
    return value == 1 ? unit : '$value ${unit}s';
  }

  /// Total price per period for [seats].
  ///
  /// No StoreKit API gives the total, so it's added up tier by tier: seats
  /// fill the lowest tier at its price, then the next tier, and so on. Without
  /// tiers, every seat costs [price]. It's a `double`, so use it for display
  /// only; Apple charges the real amount.
  double totalFor(int seats) {
    if (priceTiers.isEmpty) return seats * price;
    // StoreKit doesn't promise an order for the tiers.
    final tiers = [...priceTiers]
      ..sort((a, b) => a.minimumSeats.compareTo(b.minimumSeats));
    var total = 0.0;
    for (final tier in tiers) {
      final upper = tier.maximumSeats ?? seats; // the last tier has no maximum
      final seatsInTier =
          (seats < upper ? seats : upper) - tier.minimumSeats + 1;
      if (seatsInTier <= 0) break;
      total += seatsInTier * tier.price;
    }
    return total;
  }
}

/// The products StoreKit returned, and whether this build can buy seats.
class StoreCatalog {
  const StoreCatalog({required this.sdkSupportsSeats, required this.plans});

  factory StoreCatalog.fromMap(Map<Object?, Object?> map) => StoreCatalog(
    sdkSupportsSeats: map['sdkSupportsSeats'] as bool? ?? false,
    plans: (map['products'] as List<Object?>? ?? const [])
        .map((e) => TeamPlan.fromMap(e! as Map<Object?, Object?>))
        .toList(),
  );

  /// Whether the iOS app was built with the Xcode 27.3+ SDK and the
  /// `MULTISEAT_SDK` compilation condition, so `seats(_:)` exists.
  final bool sdkSupportsSeats;
  final List<TeamPlan> plans;
}

/// An active subscription transaction from `Transaction.currentEntitlements`.
class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.productId,
    required this.originalId,
    required this.seats,
    required this.ownershipType,
    this.jws = '',
    this.expirationDate,
    this.renewsToProductId,
    this.willAutoRenew,
    this.renewalSeats,
    this.groupRole,
  });

  factory SubscriptionEntitlement.fromMap(Map<Object?, Object?> map) =>
      SubscriptionEntitlement(
        productId: map['productId'] as String,
        originalId: map['originalId'] as String? ?? '',
        seats:
            (map['totalSeats'] as num?)?.toInt() ??
            (map['purchasedQuantity'] as num?)?.toInt() ??
            1,
        ownershipType: map['ownershipType'] as String? ?? 'PURCHASED',
        jws: map['jws'] as String? ?? '',
        expirationDate: switch (map['expirationDate']) {
          final num ms => DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
          _ => null,
        },
        renewsToProductId: map['renewsToProductId'] as String?,
        willAutoRenew: map['willAutoRenew'] as bool?,
        renewalSeats: (map['renewalSeats'] as num?)?.toInt(),
        groupRole: map['groupRole'] as String?,
      );

  final String productId;
  final String originalId;

  /// Seats in the current billing period. The bridge adds seat-addition
  /// transactions to the renewal; one transaction's `purchasedQuantity` only
  /// counts the seats it bought.
  final int seats;

  /// `PURCHASED` (bought it), `ASSIGNED` (a seat in someone's group or
  /// organization) or `FAMILY_SHARED`.
  final String ownershipType;

  /// Signed transaction to verify on your server before unlocking anything
  /// there.
  final String jws;

  /// When the current period ends, and a scheduled plan switch starts.
  final DateTime? expirationDate;

  /// `RenewalInfo.autoRenewPreference`: the plan the subscription renews to.
  final String? renewsToProductId;
  final bool? willAutoRenew;

  /// `RenewalInfo.renewalQuantity` (iOS 27.3+): seats at the next renewal,
  /// after any reduction made in Manage Subscriptions.
  final int? renewalSeats;

  /// `purchaser` or `member`, from the App Store's data sharing consent
  /// eligibility (iOS 27.3+), or `null` when it can't tell.
  final String? groupRole;

  /// Whether this account bought the subscription. The group purchaser's own
  /// seat can arrive as an `ASSIGNED` copy, so [groupRole] wins over
  /// [ownershipType].
  bool get isPurchaser =>
      groupRole == 'purchaser' ||
      (groupRole == null && ownershipType == 'PURCHASED');

  /// The other plan this subscription switches to at its next renewal, or
  /// `null` if it renews on the same plan.
  String? get scheduledPlanId =>
      renewsToProductId != null && renewsToProductId != productId
      ? renewsToProductId
      : null;
}
