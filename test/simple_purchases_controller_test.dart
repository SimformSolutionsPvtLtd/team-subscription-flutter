import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:team_subscription/config.dart';
import 'package:team_subscription/simple_purchases_controller.dart';

import 'fake_in_app_purchase.dart';

void main() {
  late FakeInAppPurchase iap;
  late SimplePurchasesController controller;
  late List<String> messages;
  late int otherTransactions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    iap = FakeInAppPurchase();
    otherTransactions = 0;
    controller = SimplePurchasesController(
      inAppPurchase: iap,
      onOtherTransaction: () => otherTransactions++,
    );
    messages = [];
    controller.messages.listen(messages.add);
    await controller.start();
  });

  test('loads both products', () {
    expect(controller.coins?.id, coinsProductId);
    expect(controller.proUnlock?.id, proUnlockProductId);
  });

  test('a bought consumable adds coins and is completed', () async {
    await controller.buyCoins();
    expect(iap.bought, [coinsProductId]);
    expect(controller.busyProductId, coinsProductId);

    iap.deliver([purchase(coinsProductId, PurchaseStatus.purchased)]);
    await pumpEventQueue();

    expect(controller.coinBalance, coinsPerPurchase);
    expect(controller.busyProductId, isNull);
    expect(iap.completed, [coinsProductId]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('coins'), coinsPerPurchase);
  });

  test('a restored consumable adds nothing', () async {
    iap.deliver([purchase(coinsProductId, PurchaseStatus.restored)]);
    await pumpEventQueue();
    expect(controller.coinBalance, 0);
  });

  test('a restored non-consumable is owned again', () async {
    await controller.restorePurchases();
    iap.deliver([purchase(proUnlockProductId, PurchaseStatus.restored)]);
    await pumpEventQueue();

    expect(iap.restoreCalls, 1);
    expect(controller.ownsPro, isTrue);
    expect(messages, ['Pro unlock restored.']);
  });

  test('a cancelled purchase clears the spinner', () async {
    await controller.buyProUnlock();
    iap.deliver([purchase(proUnlockProductId, PurchaseStatus.canceled)]);
    await pumpEventQueue();

    expect(controller.busyProductId, isNull);
    expect(controller.ownsPro, isFalse);
    expect(messages, ['Purchase cancelled.']);
  });

  test('completes a team plan transaction and re-reads entitlements', () async {
    iap.deliver([
      purchase('com.example.team.monthly', PurchaseStatus.purchased),
    ]);
    await pumpEventQueue();

    expect(otherTransactions, 1);
    expect(iap.completed, ['com.example.team.monthly']);
  });
}
