import 'package:team_subscription/storekit/models.dart';
import 'package:team_subscription/storekit/storekit_bridge.dart';

const monthlyId = 'com.example.team.monthly';
const yearlyId = 'com.example.team.yearly';

TeamPlan plan(String id, {double price = 9.99, String period = 'month'}) =>
    TeamPlan.fromMap({
      'id': id,
      'displayName': id == monthlyId ? 'Team Monthly' : 'Team Yearly',
      'description': '',
      'displayPrice': '\$$price',
      'price': price,
      'currencyCode': 'USD',
      'periodUnit': period,
      'periodValue': 1,
      'supportsMultiSeatPurchase': true,
    });

SubscriptionEntitlement entitlement({
  String productId = monthlyId,
  int seats = 5,
  String ownershipType = 'PURCHASED',
  String? groupRole,
  String? renewsToProductId,
}) => SubscriptionEntitlement.fromMap({
  'productId': productId,
  'totalSeats': seats,
  'ownershipType': ownershipType,
  'groupRole': groupRole,
  'renewsToProductId': renewsToProductId,
});

/// Stands in for the native bridge: records purchases and returns canned
/// results.
class FakeStoreKitBridge implements StoreKitBridge {
  FakeStoreKitBridge({
    List<TeamPlan>? plans,
    this.entitlements = const [],
    this.sdkSupportsSeats = true,
  }) : plans =
           plans ??
           [plan(monthlyId), plan(yearlyId, price: 99.99, period: 'year')];

  List<TeamPlan> plans;
  List<SubscriptionEntitlement> entitlements;
  bool sdkSupportsSeats;

  /// What the next purchase returns. Defaults to a fresh purchase.
  Map<Object?, Object?> Function(String productId, int? seats)? purchaseResult;

  final purchases = <({String productId, int? seats})>[];
  void Function()? transactionsUpdated;

  @override
  Future<StoreCatalog> loadProducts(List<String> productIds) async =>
      StoreCatalog(sdkSupportsSeats: sdkSupportsSeats, plans: plans);

  @override
  Future<Map<Object?, Object?>> purchase(String productId, {int? seats}) async {
    purchases.add((productId: productId, seats: seats));
    return purchaseResult?.call(productId, seats) ??
        {
          'status': 'purchased',
          'productId': productId,
          'ownershipType': 'PURCHASED',
          'purchaseDate': DateTime.now().millisecondsSinceEpoch,
        };
  }

  @override
  Future<List<SubscriptionEntitlement>> currentEntitlements() async =>
      entitlements;

  @override
  Future<void> restorePurchases() async {}

  @override
  Future<void> showManageSubscriptions() async {}

  @override
  set onTransactionsUpdated(void Function()? callback) =>
      transactionsUpdated = callback;
}
