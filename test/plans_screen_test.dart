import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:team_subscription/main.dart';
import 'package:team_subscription/simple_purchases_controller.dart';
import 'package:team_subscription/team_subscription_controller.dart';

import 'fake_in_app_purchase.dart';
import 'fake_storekit_bridge.dart';

Future<FakeStoreKitBridge> _pumpApp(
  WidgetTester tester,
  FakeStoreKitBridge bridge, {
  FakeInAppPurchase? iap,
}) async {
  SharedPreferences.setMockInitialValues({});
  final team = TeamSubscriptionController(bridge: bridge);
  final oneTime = SimplePurchasesController(
    inAppPurchase: iap ?? FakeInAppPurchase(),
  );
  await tester.runAsync(() async {
    await team.start();
    await oneTime.start();
  });
  await tester.pumpWidget(TeamSubscriptionApp(team: team, oneTime: oneTime));
  await tester.pumpAndSettle();
  return bridge;
}

void main() {
  testWidgets('shows the plans and buys the picked number of seats', (
    tester,
  ) async {
    final bridge = await _pumpApp(tester, FakeStoreKitBridge());

    expect(find.text('No team plan yet'), findsOneWidget);
    expect(find.text('Team Monthly'), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('More seats').first);
      await tester.pump();
    }
    expect(find.text(r'$29.97 / month for 3 seats'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe').first);
    await tester.pumpAndSettle();
    expect(bridge.purchases.single, (productId: monthlyId, seats: 3));
  });

  testWidgets("shows the purchaser's group and a plan switch", (tester) async {
    await _pumpApp(
      tester,
      FakeStoreKitBridge(entitlements: [entitlement(seats: 5)]),
    );

    expect(find.text('Purchaser'), findsOneWidget);
    expect(find.text('5 seats'), findsOneWidget);
    expect(find.text('Manage group'), findsOneWidget);
    expect(find.text('Add seats'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Switch plan'), 200);
    expect(find.text('Your 5 seats move to this plan.'), findsOneWidget);
  });

  testWidgets('warns when the build has no seats support', (tester) async {
    await _pumpApp(tester, FakeStoreKitBridge(sdkSupportsSeats: false));

    expect(find.textContaining('MULTISEAT_SDK'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add).first)
          .onPressed,
      isNull,
    );
  });

  testWidgets('the one-time tab buys through the plugin', (tester) async {
    final iap = FakeInAppPurchase();
    await _pumpApp(tester, FakeStoreKitBridge(), iap: iap);

    await tester.tap(find.text('One-time'));
    await tester.pumpAndSettle();
    expect(find.text('100 Coins'), findsOneWidget);
    expect(find.text('Pro Unlock'), findsOneWidget);
    expect(find.text('You have 0 coins'), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pump();
    expect(iap.bought, ['com.example.pro.unlock']);
  });
}
