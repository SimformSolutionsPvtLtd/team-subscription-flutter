import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:team_subscription/config.dart';

ProductDetails product(String id, String title, String price) => ProductDetails(
  id: id,
  title: title,
  description: '',
  price: price,
  rawPrice: double.parse(price.substring(1)),
  currencyCode: 'USD',
);

PurchaseDetails purchase(String productId, PurchaseStatus status) =>
    PurchaseDetails(
      productID: productId,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'app_store',
      ),
      transactionDate: null,
      status: status,
    )..pendingCompletePurchase = status != PurchaseStatus.pending;

/// Stands in for the `in_app_purchase` plugin: tests push updates through
/// [deliver] and read what was bought and completed.
class FakeInAppPurchase implements InAppPurchase {
  FakeInAppPurchase({List<ProductDetails>? products})
    : products =
          products ??
          [
            product(coinsProductId, '100 Coins', r'$0.99'),
            product(proUnlockProductId, 'Pro Unlock', r'$4.99'),
          ];

  final List<ProductDetails> products;
  final _stream = StreamController<List<PurchaseDetails>>.broadcast();
  final bought = <String>[];
  final completed = <String>[];
  var restoreCalls = 0;

  void deliver(List<PurchaseDetails> purchases) => _stream.add(purchases);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(
        productDetails: products.where((p) => ids.contains(p.id)).toList(),
        notFoundIDs: const [],
      );

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    bought.add(purchaseParam.productDetails.id);
    return true;
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    bought.add(purchaseParam.productDetails.id);
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async =>
      completed.add(purchase.productID);

  @override
  Future<void> restorePurchases({String? applicationUserName}) async =>
      restoreCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
