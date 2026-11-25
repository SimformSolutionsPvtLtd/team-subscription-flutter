import 'package:flutter/services.dart';

import 'models.dart';

/// Dart side of `TeamSubscriptionBridge` in
/// `ios/Runner/TeamSubscriptionBridge.swift`.
///
/// The `in_app_purchase` plugin can't pass `Product.PurchaseOption.seats(_:)`,
/// so this demo calls StoreKit 2 through one method channel.
class StoreKitBridge {
  StoreKitBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('team_subscription/storekit');

  final MethodChannel _channel;

  Future<StoreCatalog> loadProducts(List<String> productIds) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'loadProducts',
      {'productIds': productIds},
    );
    return StoreCatalog.fromMap(map ?? const {});
  }

  /// Buys [productId].
  ///
  /// With [seats] it's a team purchase, and [seats] is the total after the
  /// purchase, not the number to add: a group with 3 seats that wants 5
  /// passes 5. Without it, it's an ordinary single-person subscription.
  ///
  /// Returns the native result: `status` is `purchased`, `pending`,
  /// `cancelled` or `unknown`, and a purchased result carries the
  /// transaction's fields. Throws [PlatformException] with codes such as
  /// `SEAT_REDUCTION_NOT_ALLOWED`, `MULTI_SEAT_PURCHASE_DISABLED` or
  /// `SDK_TOO_OLD`.
  Future<Map<Object?, Object?>> purchase(String productId, {int? seats}) async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('purchase', {
      'productId': productId,
      'seats': ?seats,
    });
    return map ?? const {'status': 'unknown'};
  }

  /// `Transaction.currentEntitlements`: the source of truth for access. It
  /// includes seats someone else bought and assigned to this account.
  Future<List<SubscriptionEntitlement>> currentEntitlements() async {
    final list = await _channel.invokeListMethod<Object?>(
      'currentEntitlements',
    );
    return (list ?? const [])
        .map(
          (e) => SubscriptionEntitlement.fromMap(e! as Map<Object?, Object?>),
        )
        .toList();
  }

  /// `AppStore.sync()`. Shows an App Store sign-in prompt, so only call it
  /// when the user asks to restore.
  Future<void> restorePurchases() =>
      _channel.invokeMethod<void>('restorePurchases');

  /// Apple's Manage Subscriptions sheet, where the group purchaser invites
  /// and removes members and changes the number of seats.
  Future<void> showManageSubscriptions() =>
      _channel.invokeMethod<void>('showManageSubscriptions');

  /// Called when `Transaction.updates` delivers something: a renewal, a seat
  /// assigned by a group purchaser, a refund or a purchase made elsewhere.
  set onTransactionsUpdated(void Function()? callback) {
    _channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'transactionsUpdated') callback();
            },
    );
  }
}
