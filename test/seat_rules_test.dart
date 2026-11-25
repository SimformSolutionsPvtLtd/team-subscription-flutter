import 'package:flutter_test/flutter_test.dart';
import 'package:team_subscription/storekit/models.dart';
import 'package:team_subscription/storekit/seat_rules.dart';

import 'fake_storekit_bridge.dart';

TeamPlan _tiered(List<Map<String, Object?>> tiers) =>
    TeamPlan.fromMap({'id': monthlyId, 'price': 9.99, 'priceTiers': tiers});

const _tier1 = {
  'minimumSeats': 1,
  'maximumSeats': 5,
  'price': 9.99,
  'displayPrice': r'$9.99',
};
const _tier2 = {
  'minimumSeats': 6,
  'maximumSeats': 10,
  'price': 7.99,
  'displayPrice': r'$7.99',
};
const _tier3 = {'minimumSeats': 11, 'price': 5.99, 'displayPrice': r'$5.99'};

void main() {
  group('seat prices', () {
    test("adds up tiers seat by seat (Apple's example)", () {
      final p = _tiered([_tier1, _tier2, _tier3]);
      expect(p.totalFor(8), closeTo(73.92, 0.001)); // 5 × 9.99 + 3 × 7.99
      expect(p.totalFor(3), closeTo(29.97, 0.001));
      expect(p.totalFor(12), closeTo(101.88, 0.001));
    });

    test('adds up tiers that arrive out of order', () {
      expect(
        _tiered([_tier3, _tier2, _tier1]).totalFor(8),
        closeTo(73.92, 0.001),
      );
    });

    test('charges the base price per seat without tiers', () {
      expect(_tiered([]).totalFor(4), closeTo(39.96, 0.001));
    });

    test('uses the period total, not the seat-addition quantity', () {
      // Bought 3, added 2: currentEntitlements returns the 2-seat addition,
      // and the bridge reports the period's total.
      final e = SubscriptionEntitlement.fromMap({
        'productId': monthlyId,
        'purchasedQuantity': 2,
        'totalSeats': 5,
        'ownershipType': 'PURCHASED',
      });
      expect(e.seats, 5);
    });
  });

  group('who is the purchaser', () {
    test('trusts the App Store role over the ownership type', () {
      // The purchaser's own seat can be an ASSIGNED copy of their purchase.
      expect(
        entitlement(
          ownershipType: 'ASSIGNED',
          groupRole: 'purchaser',
        ).isPurchaser,
        isTrue,
      );
      expect(
        entitlement(ownershipType: 'ASSIGNED', groupRole: 'member').isPurchaser,
        isFalse,
      );
    });

    test('falls back to the ownership type without a role', () {
      expect(entitlement(ownershipType: 'PURCHASED').isPurchaser, isTrue);
      expect(entitlement(ownershipType: 'ASSIGNED').isPurchaser, isFalse);
    });

    test("shows the PURCHASED transaction over the purchaser's copy", () {
      final copy = entitlement(
        ownershipType: 'ASSIGNED',
        groupRole: 'purchaser',
      );
      final purchased = entitlement(groupRole: 'purchaser');
      expect(pickActiveSubscription([copy, purchased]), same(purchased));
    });

    test('prefers a group this account bought over a seat in another', () {
      final seat = entitlement(ownershipType: 'ASSIGNED', groupRole: 'member');
      final own = entitlement(
        ownershipType: 'ASSIGNED',
        groupRole: 'purchaser',
      );
      expect(pickActiveSubscription([seat, own]), same(own));
    });
  });

  group('seat picker', () {
    final active = entitlement(seats: 5);

    test('starts one above the seats owned on the current plan', () {
      expect(initialSeats(monthlyId, active), 6);
      expect(isSeatReduction(monthlyId, 5, active), isTrue);
      expect(isSeatReduction(monthlyId, 6, active), isFalse);
    });

    test("keeps the group's seats when switching plans", () {
      expect(initialSeats(yearlyId, active), 5);
      expect(isSeatReduction(yearlyId, 4, active), isTrue);
      expect(isSeatReduction(yearlyId, 5, active), isFalse);
    });

    test('starts at one seat without a group, or as a member', () {
      expect(initialSeats(monthlyId, null), 1);
      final member = entitlement(
        ownershipType: 'ASSIGNED',
        groupRole: 'member',
      );
      expect(initialSeats(monthlyId, member), 1);
    });
  });

  group('purchase results', () {
    final startedAt = DateTime.fromMillisecondsSinceEpoch(1794909054000);

    test('a new purchase is not stale', () {
      expect(
        isStalePurchaseResult({
          'ownershipType': 'PURCHASED',
          'purchaseDate': 1794909072000, // 18 s after starting
        }, startedAt),
        isFalse,
      );
    });

    test('an assigned or old transaction is stale', () {
      expect(
        isStalePurchaseResult({
          'ownershipType': 'ASSIGNED',
          'purchaseDate': 1794909072000,
        }, startedAt),
        isTrue,
      );
      expect(
        isStalePurchaseResult({
          'ownershipType': 'PURCHASED',
          'purchaseDate': 1794898985000, // three hours earlier
        }, startedAt),
        isTrue,
      );
    });

    test('spots a downgrade scheduled for the next renewal', () {
      expect(
        isScheduledDowngrade({
          'status': 'purchased',
          'productId': yearlyId,
        }, monthlyId),
        isTrue,
      );
      expect(
        isScheduledDowngrade({
          'status': 'purchased',
          'productId': monthlyId,
        }, monthlyId),
        isFalse,
      );
    });
  });
}
