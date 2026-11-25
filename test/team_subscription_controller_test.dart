import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:team_subscription/team_subscription_controller.dart';

import 'fake_storekit_bridge.dart';

Future<(TeamSubscriptionController, FakeStoreKitBridge)> _start(
  FakeStoreKitBridge bridge,
) async {
  final controller = TeamSubscriptionController(bridge: bridge);
  await controller.start();
  return (controller, bridge);
}

void main() {
  test('one seat with no group is an ordinary subscription', () async {
    final (c, bridge) = await _start(FakeStoreKitBridge());
    final monthly = c.planFor(monthlyId)!;

    expect(c.actionFor(monthly), PlanAction.subscribe);
    expect(c.seatsFor(monthly), 1);
    await c.buy(monthly);

    expect(bridge.purchases.single, (productId: monthlyId, seats: null));
  });

  test('a new group sends seats(total)', () async {
    final (c, bridge) = await _start(FakeStoreKitBridge());
    final monthly = c.planFor(monthlyId)!;

    c.setSeats(monthly, 5);
    await c.buy(monthly);

    expect(bridge.purchases.single, (productId: monthlyId, seats: 5));
  });

  test('adding seats sends the new total, starting one above', () async {
    final (c, bridge) = await _start(
      FakeStoreKitBridge(entitlements: [entitlement(seats: 3)]),
    );
    final monthly = c.planFor(monthlyId)!;

    expect(c.actionFor(monthly), PlanAction.addSeats);
    expect(c.minSeatsFor(monthly), 4);
    c.setSeats(monthly, 2); // clamped to the minimum
    expect(c.seatsFor(monthly), 4);
    c.setSeats(monthly, 5);
    await c.buy(monthly);

    expect(bridge.purchases.single, (productId: monthlyId, seats: 5));
  });

  test("a plan switch keeps the group's seats", () async {
    final (c, bridge) = await _start(
      FakeStoreKitBridge(entitlements: [entitlement(seats: 5)]),
    );
    final yearly = c.planFor(yearlyId)!;

    expect(c.actionFor(yearly), PlanAction.switchPlan);
    expect(c.seatsFor(yearly), 5);
    await c.buy(yearly);

    expect(bridge.purchases.single, (productId: yearlyId, seats: 5));
  });

  test('a member starts their own group from one seat', () async {
    final (c, _) = await _start(
      FakeStoreKitBridge(
        entitlements: [
          entitlement(ownershipType: 'ASSIGNED', groupRole: 'member'),
        ],
      ),
    );

    expect(c.hasAccess, isTrue);
    expect(c.ownedSeats, 0);
    expect(c.actionFor(c.planFor(monthlyId)!), PlanAction.subscribe);
  });

  test('a scheduled downgrade blocks buying that plan again', () async {
    final (c, bridge) = await _start(
      FakeStoreKitBridge(
        entitlements: [
          entitlement(productId: yearlyId, renewsToProductId: monthlyId),
        ],
      ),
    );
    final monthly = c.planFor(monthlyId)!;

    expect(c.actionFor(monthly), PlanAction.scheduled);
    await c.buy(monthly);
    expect(bridge.purchases, isEmpty);
  });

  test('reports a downgrade that starts at renewal', () async {
    final bridge =
        FakeStoreKitBridge(
            entitlements: [entitlement(productId: yearlyId, seats: 5)],
          )
          ..purchaseResult = (_, _) => {
            'status': 'purchased',
            'productId': yearlyId, // StoreKit returns the current plan
            'ownershipType': 'PURCHASED',
          };
    final (c, _) = await _start(bridge);
    final messages = <String>[];
    c.messages.listen(messages.add);

    await c.buy(c.planFor(monthlyId)!);
    await pumpEventQueue();

    expect(messages, ['Team Monthly starts at your next renewal.']);
  });

  test('reports an old transaction returned by purchase()', () async {
    final bridge = FakeStoreKitBridge()
      ..purchaseResult = (id, _) => {
        'status': 'purchased',
        'productId': id,
        'ownershipType': 'PURCHASED',
        'purchaseDate': DateTime.now()
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      };
    final (c, _) = await _start(bridge);
    final messages = <String>[];
    c.messages.listen(messages.add);

    await c.buy(c.planFor(monthlyId)!);
    await pumpEventQueue();

    expect(messages.single, contains('earlier purchase'));
  });

  test('shows StoreKit errors', () async {
    final bridge = FakeStoreKitBridge(entitlements: [entitlement(seats: 5)])
      ..purchaseResult = (_, _) => throw PlatformException(
        code: 'SEAT_REDUCTION_NOT_ALLOWED',
        message: 'Pick more seats than you have now.',
      );
    final (c, _) = await _start(bridge);
    final messages = <String>[];
    c.messages.listen(messages.add);

    await c.buy(c.planFor(monthlyId)!);
    await pumpEventQueue();

    expect(messages, ['Pick more seats than you have now.']);
    expect(c.busyPlanId, isNull);
  });

  test('re-reads entitlements when StoreKit reports an update', () async {
    final (c, bridge) = await _start(FakeStoreKitBridge());
    expect(c.hasAccess, isFalse);

    // A group purchaser assigned this account a seat.
    bridge.entitlements = [
      entitlement(ownershipType: 'ASSIGNED', groupRole: 'member'),
    ];
    bridge.transactionsUpdated!();
    await pumpEventQueue();

    expect(c.hasAccess, isTrue);
  });

  test('only counts entitlements for the team plans', () async {
    final (c, _) = await _start(
      FakeStoreKitBridge(
        entitlements: [entitlement(productId: 'com.example.other')],
      ),
    );
    expect(c.active, isNull);
  });
}
