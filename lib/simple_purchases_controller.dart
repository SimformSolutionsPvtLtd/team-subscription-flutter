import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// One-time purchases (a consumable and a non-consumable) through the
/// `in_app_purchase` plugin.
///
/// They don't need seats, so the plugin handles them. Team plans need
/// `Product.PurchaseOption.seats(_:)`, which the plugin can't pass, so they go
/// through the StoreKit bridge instead. Both can live in the same app.
class SimplePurchasesController extends ChangeNotifier {
  SimplePurchasesController({
    InAppPurchase? inAppPurchase,
    this.onOtherTransaction,
  }) : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  /// Called when the plugin delivers a transaction this controller doesn't
  /// sell, such as a team plan renewal. The app re-reads entitlements.
  final void Function()? onOtherTransaction;

  static const _coinsKey = 'coins';
  static const _proKey = 'ownsPro';

  bool isLoading = true;
  bool isStoreAvailable = false;
  ProductDetails? coins;
  ProductDetails? proUnlock;
  int coinBalance = 0;
  bool ownsPro = false;

  /// The product whose purchase is in progress.
  String? busyProductId;

  StreamSubscription<List<PurchaseDetails>>? _purchases;
  final _messages = StreamController<String>.broadcast();

  /// One-off messages for the user, such as purchase results.
  Stream<String> get messages => _messages.stream;

  Future<void> start() async {
    // Listen before anything else: the plugin delivers transactions left
    // over from earlier launches as soon as the stream has a listener.
    _purchases = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => _messages.add('Purchase failed: $e'),
    );
    final prefs = await SharedPreferences.getInstance();
    coinBalance = prefs.getInt(_coinsKey) ?? 0;
    ownsPro = prefs.getBool(_proKey) ?? false;

    isStoreAvailable = await _iap.isAvailable();
    if (isStoreAvailable) {
      final response = await _iap.queryProductDetails({
        coinsProductId,
        proUnlockProductId,
      });
      for (final product in response.productDetails) {
        if (product.id == coinsProductId) coins = product;
        if (product.id == proUnlockProductId) proUnlock = product;
      }
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> buyCoins() => _buy(coins, consumable: true);

  Future<void> buyProUnlock() => _buy(proUnlock, consumable: false);

  Future<void> _buy(ProductDetails? product, {required bool consumable}) async {
    if (product == null || busyProductId != null) return;
    busyProductId = product.id;
    notifyListeners();
    final param = PurchaseParam(productDetails: product);
    try {
      // The result arrives on purchaseStream, not here.
      final started = consumable
          ? await _iap.buyConsumable(purchaseParam: param)
          : await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) _finishBusy('The purchase did not start.');
    } catch (e) {
      _finishBusy('Purchase failed: $e');
    }
  }

  /// Re-delivers owned non-consumables as `restored` on [purchaseStream].
  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      debugPrint(
        '[iap] ${purchase.productID}: ${purchase.status.name} '
        'pendingComplete=${purchase.pendingCompletePurchase} '
        'error=${purchase.error?.message}',
      );
      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue; // Ask to Buy and similar: wait for the next update.
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(purchase);
        case PurchaseStatus.error:
          _finishBusy(
            'Purchase failed: ${purchase.error?.message ?? 'unknown error'}',
          );
        case PurchaseStatus.canceled:
          _finishBusy('Purchase cancelled.');
      }
      // Finish every transaction the stream delivers, even one this
      // controller doesn't sell: an unfinished transaction can come back
      // later from purchase() as if it were new.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _deliver(PurchaseDetails purchase) async {
    final prefs = await SharedPreferences.getInstance();
    if (purchase.productID == coinsProductId) {
      // A restored consumable was already delivered.
      if (purchase.status == PurchaseStatus.purchased) {
        coinBalance += coinsPerPurchase;
        await prefs.setInt(_coinsKey, coinBalance);
        _finishBusy('Added $coinsPerPurchase coins.');
      }
    } else if (purchase.productID == proUnlockProductId) {
      final wasOwned = ownsPro;
      ownsPro = true;
      await prefs.setBool(_proKey, true);
      if (wasOwned) {
        busyProductId = null;
      } else {
        _finishBusy(
          purchase.status == PurchaseStatus.restored
              ? 'Pro unlock restored.'
              : 'Pro unlocked.',
        );
      }
    } else {
      onOtherTransaction?.call();
    }
    notifyListeners();
  }

  void _finishBusy(String message) {
    busyProductId = null;
    _messages.add(message);
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_purchases?.cancel());
    unawaited(_messages.close());
    super.dispose();
  }
}
