# Team Subscriptions in Flutter

A small Flutter app that sells an App Store subscription to a team: one person buys seats, invites people, and everyone gets access on their own Apple Account. Apple calls these **multiseat subscriptions** (Group Purchases), new in iOS 27.3.

The `in_app_purchase` plugin can't buy seats yet, so team plans go through a small StoreKit 2 bridge in Swift. Ordinary one-time purchases stay on the plugin, and the app shows both side by side. It's the companion project to the Medium article *Team Subscriptions in Flutter with Multiseat Purchases*.

## What it does

**Team plans tab** (StoreKit bridge)

- Loads the team plans, with the price for any number of seats, including volume-discount tiers.
- Starts a group, adds seats, and switches the group between plans without losing seats.
- Shows "Starts at renewal" for a downgrade that StoreKit schedules for the next renewal.
- Grants access from `Transaction.currentEntitlements`, including seats assigned by someone else's group.
- Tells the group purchaser from a member, even when the purchaser's own seat arrives as an `ASSIGNED` copy.
- Opens Manage Subscriptions, where the purchaser invites and removes members and reduces seats.
- Listens to `Transaction.updates`, so a seat a member is given shows up without restarting the app.

**One-time tab** (`in_app_purchase` plugin)

- A consumable (coins) and a non-consumable (an unlock), bought, delivered and completed through the plugin's purchase stream.

**Restore** in the app bar restores both: `AppStore.sync()` for the team plans, and the plugin's `restorePurchases()` for the unlock.

## Requirements

- Xcode 27.3 or later, and iOS 27.3 or later to buy seats. The minimum deployment target is iOS 15, but seat pricing, the purchaser/member role and the invitation sheet need iOS 27.3.
- Flutter 3.41 or later (`in_app_purchase_storekit` 0.4.17 needs it).
- An Apple Developer account, and two sandbox accounts to test with: a purchaser and a member.

## Set up

### 1. App Store Connect

1. Create two auto-renewable subscriptions **in the same subscription group**, for example Team Monthly and Team Yearly. Seats belong to the group, so switching between them keeps the seats.
2. Open each subscription, click **Edit** next to **Purchase Options**, choose **Yes, allow multiseat purchases**, pick where it can be sold, and click **Confirm**. New subscriptions allow it by default.
3. Optional: set volume-discount tiers through the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi/managing-auto-renewable-subscriptions). The web UI can't set them yet.
4. For the one-time tab, create a consumable and a non-consumable.

In the sandbox, every subscription allows multiseat purchases whatever these settings say.

### 2. Your IDs (kept out of git)

Product IDs, the bundle ID and the signing team live in two git-ignored files. Copy the examples and fill them in:

```bash
cp config.example.json config.json
```

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
```

| File | What goes in it |
| --- | --- |
| `config.json` | `TEAM_PLAN_IDS` (comma-separated, one subscription group), `COINS_PRODUCT_ID`, `PRO_UNLOCK_PRODUCT_ID`, `COINS_PER_PURCHASE` |
| `ios/Flutter/Local.xcconfig` | `PRODUCT_BUNDLE_IDENTIFIER` (must match your app in App Store Connect) and `DEVELOPMENT_TEAM` |

Without them, the app builds with placeholder IDs and StoreKit finds no products.

### 3. Run

```bash
flutter run --dart-define-from-file=config.json
```

VS Code picks up the same flag from `.vscode/launch.json`. To run from Xcode, run the `flutter` command once first, so `ios/Flutter/Generated.xcconfig` carries the product IDs.

Sign in with a sandbox account when StoreKit asks, or under **Settings → Developer → Sandbox Apple Account**.

**Test purchases on a device.** Products load in the iOS 27.3 Simulator, but sandbox sign-in failed there in our testing (StoreKit logged `Authenticate failed for sandbox`), so every purchase came back cancelled.

**White screen on a device?** On iOS 26 and later, a debug build waits for Xcode's debugger (LLDB) to attach, and `flutter run` can hang there. Run from Xcode instead, or install a profile build without the debugger:

```bash
flutter build ios --profile --config-only --dart-define-from-file=config.json
```

Then press **Run** in Xcode, or build and install it with `xcodebuild` and `xcrun devicectl device install app`.

### Building with an older Xcode

The multiseat APIs exist only in the Xcode 27.3 SDK, so the Swift code that uses them sits behind the `MULTISEAT_SDK` compilation condition, which is on in this project. To build with an older Xcode, remove `MULTISEAT_SDK` from **Runner → Build Settings → Active Compilation Conditions** (Debug, Release and Profile). The app then shows a banner and can only sell single-person subscriptions.

### Xcode 27.3 beta and Flutter 3.44

With the Xcode 27.3 beta, `flutter build ios --simulator` fails in "Prepare Flutter Framework Script", because the beta reports no architecture for the "Any iOS Simulator Device" destination. Build for a specific simulator instead:

```bash
flutter build ios --simulator --config-only --dart-define-from-file=config.json
```

```bash
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 18 Pro' build
```

## Try it

| Step | Account | What to check |
| --- | --- | --- |
| Buy 3 seats on Monthly | Purchaser | Apple's invitation sheet opens; the app shows **Purchaser · 3 seats** |
| Add 2 seats | Purchaser | The picker starts at 4; afterwards the app shows **5 seats**, not 2 |
| Switch to Yearly | Purchaser | The picker starts at 5 and the button says **Switch plan** |
| Switch back to Monthly | Purchaser | The Monthly button says **Starts at renewal** |
| Add the member | Purchaser | Sandbox accounts can't accept invitation links, so add the member by email in the purchaser's sandbox subscription settings |
| Open the app | Member | It shows **Member** and grants access, without a purchase |
| Buy coins, then the unlock | Either | The balance goes up; the unlock shows **Owned**, and comes back with **Restore** after reinstalling |

## How it works

```
HomeScreen ─ Team plans tab ─────────────── One-time tab
                 │                               │
TeamSubscriptionController            SimplePurchasesController
                 │  seat rules                   │
StoreKitBridge (Dart)                  in_app_purchase plugin
                 │  MethodChannel('team_subscription/storekit')
TeamSubscriptionBridge (Swift, StoreKit 2)
     • loadProducts             • restorePurchases
     • purchase                 • showManageSubscriptions
     • currentEntitlements      ◂ transactionsUpdated (Transaction.updates)
```

| File | What it does |
| --- | --- |
| [`ios/Runner/TeamSubscriptionBridge.swift`](ios/Runner/TeamSubscriptionBridge.swift) | StoreKit 2: products and seat prices, purchases with `seats(_:)`, entitlements and seat totals, the group role, the transaction listener |
| [`ios/Runner/AppDelegate.swift`](ios/Runner/AppDelegate.swift) | Registers the bridge once Flutter's engine exists (UIScene lifecycle) |
| [`lib/config.dart`](lib/config.dart) | Reads the product IDs from `config.json` |
| [`lib/storekit/storekit_bridge.dart`](lib/storekit/storekit_bridge.dart) | Dart side of the method channel |
| [`lib/storekit/models.dart`](lib/storekit/models.dart) | Plans, price tiers and the seat total, entitlements |
| [`lib/storekit/seat_rules.dart`](lib/storekit/seat_rules.dart) | Which entitlement to show, where the seat picker starts, seat reductions, stale results, scheduled downgrades |
| [`lib/team_subscription_controller.dart`](lib/team_subscription_controller.dart) | Team plans: loads plans, reads entitlements, buys, restores |
| [`lib/simple_purchases_controller.dart`](lib/simple_purchases_controller.dart) | One-time purchases through the plugin |
| [`lib/screens/`](lib/screens), [`lib/widgets/`](lib/widgets) | The UI |

### The rules the code follows

- **`seats(_:)` takes the total after the purchase**, not the number to add. A group with 3 seats that wants 5 buys `.seats(5)`. Asking for fewer fails with `seatReductionNotAllowed`; seats are reduced in Manage Subscriptions, from the next renewal.
- **One seat with no group is an ordinary subscription.** Anything else is bought with `seats(_:)`.
- **Seats belong to the subscription group.** The app reads entitlements for every plan in the group, so a plan switch sends the group's current total.
- **Adding seats creates a separate transaction** whose `purchasedQuantity` is only the seats added. The bridge adds up the period's unrevoked transactions to get the total.
- **Downgrades wait for renewal.** `purchase()` returns the current plan's transaction, and `RenewalInfo.autoRenewPreference` holds the plan it will renew to.
- **`purchase()` can return an old transaction.** The bridge finishes unfinished subscription transactions at launch, the plugin's listener completes everything it delivers, and the app treats a result that isn't `PURCHASED`, or is dated well before the tap, as stale.
- **The bridge and the plugin don't step on each other.** The bridge finishes only auto-renewable transactions; one-time purchases are left for the plugin to deliver and complete.
- **The purchaser can look like a member.** The app trusts the App Store's data sharing consent eligibility over `ownershipType`.
- **Access comes from entitlements, never from the purchase result.** If access unlocks anything on your server, verify each transaction's JWS there.
- **The payment sheet is anchored to the Flutter view** with `purchase(confirmIn:options:)`. Without it, purchases stay pending forever on iOS 27; `in_app_purchase_storekit` 0.4.17 does the same for the plugin.

## Tests

The seat rules, the price total, both controllers and the main screens run without a device:

```bash
flutter test
```

`test/fake_storekit_bridge.dart` and `test/fake_in_app_purchase.dart` stand in for the native bridge and the plugin, so the tests cover what the app sends to StoreKit (for example `seats: 5` on a plan switch) and how it reacts to each kind of result.

## Before you ship

- Group Purchases aren't live on the App Store yet; Apple says they arrive this winter. The steps in **Try it** for the purchaser and the one-time purchases were tested in the sandbox on an iPhone running iOS 27.2.1, built with Xcode 27.3 beta. The purchaser/member role and seat price tiers need iOS 27.3, and the APIs may still change.
- In production, invitations are links the purchaser shares, and invitees accept them on an Apple device. Their `ASSIGNED` transaction arrives through `Transaction.updates`, which this app already listens to.
- Apple only contacts the purchaser about billing problems. Tell members in your app.
- Coins are stored on the device with `shared_preferences` to keep the demo small. A real app keeps balances on its server.

## Further reading

- [Offer subscriptions to groups and organizations](https://developer.apple.com/videos/play/wwdc2026/391/) (WWDC26)
- [Supporting multiseat purchases in your app](https://developer.apple.com/documentation/storekit/supporting-multiseat-purchases-in-your-app)
- [Managing the life cycle of multiseat subscriptions](https://developer.apple.com/documentation/storekit/managing-the-life-cycle-of-multiseat-subscriptions)
- [Testing multiseat subscriptions](https://developer.apple.com/documentation/storekit/testing-multiseat-subscriptions)

## License

MIT. See [LICENSE](LICENSE).
