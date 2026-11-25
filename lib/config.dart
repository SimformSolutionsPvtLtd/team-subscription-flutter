/// Product IDs, read at build time from `config.json`:
///
/// ```bash
/// flutter run --dart-define-from-file=config.json
/// ```
///
/// Copy `config.example.json` to `config.json` (git-ignored) and put your own
/// App Store Connect product IDs in it. Without it, the placeholders below
/// are used and StoreKit finds no products.
library;

/// The team plans: auto-renewable subscriptions with multiseat purchases
/// allowed, all in ONE subscription group. Seats belong to the group, so
/// switching between these plans keeps the group's seats.
final List<String> teamPlanIds = _ids(
  const String.fromEnvironment(
    'TEAM_PLAN_IDS',
    defaultValue: 'com.example.team.monthly,com.example.team.yearly',
  ),
);

/// A consumable, bought through the `in_app_purchase` plugin.
const coinsProductId = String.fromEnvironment(
  'COINS_PRODUCT_ID',
  defaultValue: 'com.example.coins',
);

/// A non-consumable, bought through the `in_app_purchase` plugin.
const proUnlockProductId = String.fromEnvironment(
  'PRO_UNLOCK_PRODUCT_ID',
  defaultValue: 'com.example.pro.unlock',
);

/// Coins added for each consumable purchase. Match your product's
/// description in App Store Connect.
const coinsPerPurchase = int.fromEnvironment(
  'COINS_PER_PURCHASE',
  defaultValue: 100,
);

/// A group subscription can have up to 100 seats.
const maxSeats = 100;

List<String> _ids(String csv) => [
  for (final id in csv.split(','))
    if (id.trim().isNotEmpty) id.trim(),
];
