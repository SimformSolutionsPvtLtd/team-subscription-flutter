import Flutter
import StoreKit
import UIKit

/// StoreKit 2 bridge for team (multiseat) subscriptions.
///
/// The Flutter `in_app_purchase` plugin can't pass
/// `Product.PurchaseOption.seats(_:)`, so this demo talks to StoreKit 2
/// directly over one method channel:
///
/// | Dart → Swift                      | What it does                                  |
/// | --------------------------------- | --------------------------------------------- |
/// | `loadProducts`                    | Names, prices and seat price tiers            |
/// | `purchase`                        | Buys a plan, with `seats(_:)` for a team      |
/// | `currentEntitlements`             | Active subscriptions, seat totals, group role |
/// | `restorePurchases`                | `AppStore.sync()`                             |
/// | `showManageSubscriptions`         | Apple's Manage Subscriptions sheet            |
///
/// Swift → Dart: `transactionsUpdated` whenever `Transaction.updates`
/// delivers a renewal, a seat assigned by a group purchaser, a refund or a
/// purchase made on another device.
///
/// `seats(_:)` and the other multiseat APIs only exist in the Xcode 27.3+
/// SDK. They're compiled only when the `MULTISEAT_SDK` Swift compilation
/// condition is set (Runner target > Build Settings > Active Compilation
/// Conditions). Remove it to build with an older Xcode; seat purchases then
/// fail with `SDK_TOO_OLD`.
enum TeamSubscriptionBridge {
  static let channelName = "team_subscription/storekit"

  #if MULTISEAT_SDK
  static let sdkSupportsSeats = true
  #else
  static let sdkSupportsSeats = false
  #endif

  struct BridgeError: Error {
    let code: String
    let message: String
  }

  private static var channel: FlutterMethodChannel?
  private static var updatesTask: Task<Void, Never>?

  // MARK: - Setup

  /// Registers the method channel and starts listening for transactions.
  /// Call once, from `didInitializeImplicitFlutterEngine`.
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler(handle)
    self.channel = channel
    startTransactionListener()
  }

  /// Finishes the subscription transactions StoreKit delivers outside
  /// `purchase()`, and tells Dart to re-read entitlements.
  ///
  /// Transactions left unfinished from an earlier launch are finished first:
  /// otherwise StoreKit can hand one back from the next `purchase()` call as
  /// if it were new ("purchase() can return an old transaction").
  ///
  /// Only auto-renewable subscriptions (the team plans) are finished here.
  /// One-time purchases belong to the `in_app_purchase` plugin, which must
  /// deliver a consumable to Dart before it's finished.
  private static func startTransactionListener() {
    updatesTask?.cancel()
    updatesTask = Task.detached {
      var finishedAny = false
      for await verification in Transaction.unfinished {
        if case .verified(let transaction) = verification,
          transaction.productType == .autoRenewable
        {
          await transaction.finish()
          finishedAny = true
        }
      }
      if finishedAny { await notifyTransactionsUpdated() }

      for await verification in Transaction.updates {
        guard case .verified(let transaction) = verification,
          transaction.productType == .autoRenewable
        else { continue }
        await transaction.finish()
        await notifyTransactionsUpdated()
      }
    }
  }

  @MainActor
  private static func notifyTransactionsUpdated() {
    channel?.invokeMethod("transactionsUpdated", arguments: nil)
  }

  // MARK: - Method calls

  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    Task { @MainActor in
      do {
        switch call.method {
        case "loadProducts":
          result(try await loadProducts(ids: args["productIds"] as? [String] ?? []))
        case "purchase":
          result(
            try await purchase(
              productId: try string(args, "productId"),
              seats: args["seats"] as? Int,
              viewController: try currentViewController()
            )
          )
        case "currentEntitlements":
          result(await currentEntitlements())
        case "restorePurchases":
          try await AppStore.sync()
          result(nil)
        case "showManageSubscriptions":
          try await showManageSubscriptions(viewController: try currentViewController())
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch let error as BridgeError {
        result(FlutterError(code: error.code, message: error.message, details: nil))
      } catch {
        result(FlutterError(code: "STOREKIT_ERROR", message: error.localizedDescription, details: "\(error)"))
      }
    }
  }

  /// The top view controller of the active window scene. With the UIScene
  /// lifecycle there's no window at launch, so it's looked up per call.
  @MainActor
  private static func currentViewController() throws -> UIViewController {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window =
      scenes.lazy.flatMap { $0.windows }.first { $0.isKeyWindow }
      ?? scenes.first?.windows.first
    guard var viewController = window?.rootViewController else {
      throw BridgeError(code: "NO_VIEW_CONTROLLER", message: "No window to present StoreKit UI in.")
    }
    while let presented = viewController.presentedViewController {
      viewController = presented
    }
    return viewController
  }

  private static func string(_ args: [String: Any], _ key: String) throws -> String {
    guard let value = args[key] as? String, !value.isEmpty else {
      throw BridgeError(code: "INVALID_ARGUMENT", message: "Missing \(key)")
    }
    return value
  }

  // MARK: - Products

  /// Products in the order StoreKit returns them, each with its seat price
  /// tiers (iOS 27.3+).
  private static func loadProducts(ids: [String]) async throws -> [String: Any] {
    let products = try await Product.products(for: ids)
    return [
      "sdkSupportsSeats": sdkSupportsSeats,
      "products": products.map(productMap),
    ]
  }

  private static func productMap(_ product: Product) -> [String: Any] {
    var map: [String: Any] = [
      "id": product.id,
      "displayName": product.displayName,
      "description": product.description,
      "displayPrice": product.displayPrice,
      "price": NSDecimalNumber(decimal: product.price).doubleValue,
      "currencyCode": product.priceFormatStyle.currencyCode,
    ]
    if let subscription = product.subscription {
      map["subscriptionGroupId"] = subscription.subscriptionGroupID
      map["periodValue"] = subscription.subscriptionPeriod.value
      map["periodUnit"] = periodUnit(subscription.subscriptionPeriod.unit)
    }
    #if MULTISEAT_SDK
    if #available(iOS 27.3, *) {
      map["supportsMultiSeatPurchase"] = product.supportsMultiSeatPurchase
      map["priceTiers"] = seatPriceTiers(product)
    }
    #endif
    return map
  }

  private static func periodUnit(_ unit: Product.SubscriptionPeriod.Unit) -> String {
    switch unit {
    case .day: return "day"
    case .week: return "week"
    case .month: return "month"
    case .year: return "year"
    @unknown default: return "unknown"
    }
  }

  #if MULTISEAT_SDK
  /// The seat price tiers of the subscription's `.seatBased` pricing terms.
  /// StoreKit doesn't promise an order, so Dart sorts them.
  @available(iOS 27.3, *)
  private static func seatPriceTiers(_ product: Product) -> [[String: Any]] {
    for terms in product.subscription?.pricingTerms ?? [] {
      guard case .seatBased(let seatPricing) = terms.pricingModel else { continue }
      return seatPricing.priceTiers.map { tier in
        var map: [String: Any] = [
          "minimumSeats": tier.minimumSeats,
          "price": NSDecimalNumber(decimal: tier.billingInfo.price).doubleValue,
          "displayPrice": tier.billingInfo.displayPrice,
        ]
        if let maximumSeats = tier.maximumSeats {
          map["maximumSeats"] = maximumSeats
        }
        return map
      }
    }
    return []
  }
  #endif

  // MARK: - Purchase

  /// Buys [productId]. With [seats], it's a team (group) purchase and
  /// `seats` is the total after the purchase, not the number to add.
  /// Without it, it's an ordinary single-person subscription.
  private static func purchase(
    productId: String,
    seats: Int?,
    viewController: UIViewController
  ) async throws -> [String: Any] {
    guard let product = try await Product.products(for: [productId]).first else {
      throw BridgeError(code: "PRODUCT_NOT_FOUND", message: productId)
    }

    var options: Set<Product.PurchaseOption> = []
    if let seats {
      #if MULTISEAT_SDK
      options.insert(.seats(seats))
      #else
      throw BridgeError(
        code: "SDK_TOO_OLD",
        message: "Build with Xcode 27.3+ and the MULTISEAT_SDK compilation condition to buy seats."
      )
      #endif
    }

    let purchaseResult: Product.PurchaseResult
    do {
      purchaseResult = try await confirmPurchase(of: product, options: options, in: viewController)
    } catch {
      throw mapPurchaseError(error)
    }

    switch purchaseResult {
    case .success(let verification):
      guard case .verified(let transaction) = verification else {
        throw BridgeError(code: "UNVERIFIED_TRANSACTION", message: "StoreKit couldn't verify the transaction.")
      }
      var map = transactionMap(transaction, jws: verification.jwsRepresentation)
      map["status"] = "purchased"
      // Access comes from currentEntitlements, which still returns a
      // finished transaction, so finish it straight away.
      await transaction.finish()
      return map
    case .pending:
      return ["status": "pending"]
    case .userCancelled:
      return ["status": "cancelled"]
    @unknown default:
      return ["status": "unknown"]
    }
  }

  /// Anchors the payment sheet to the Flutter view. The scene-less
  /// `purchase(options:)` leaves StoreKit to find a window itself, which
  /// fails on iOS 27 and leaves the purchase pending forever.
  @MainActor
  private static func confirmPurchase(
    of product: Product,
    options: Set<Product.PurchaseOption>,
    in viewController: UIViewController
  ) async throws -> Product.PurchaseResult {
    if #available(iOS 18.2, *) {
      return try await product.purchase(confirmIn: viewController, options: options)
    }
    if #available(iOS 17.0, *), let windowScene = viewController.view.window?.windowScene {
      return try await product.purchase(confirmIn: windowScene, options: options)
    }
    return try await product.purchase(options: options)
  }

  private static func mapPurchaseError(_ error: Error) -> Error {
    #if MULTISEAT_SDK
    if #available(iOS 27.3, *), let purchaseError = error as? Product.PurchaseError {
      switch purchaseError {
      case .multiSeatPurchaseDisabled:
        return BridgeError(
          code: "MULTI_SEAT_PURCHASE_DISABLED",
          message: "This subscription doesn't allow multiseat purchases."
        )
      case .seatReductionNotAllowed:
        return BridgeError(
          code: "SEAT_REDUCTION_NOT_ALLOWED",
          message: "Pick more seats than you have now. Reduce seats in Manage Subscriptions."
        )
      default:
        break
      }
    }
    #endif
    return error
  }

  // MARK: - Entitlements

  /// Active, unrevoked subscriptions, including seats that a group purchaser
  /// or an organization assigned to this account.
  private static func currentEntitlements() async -> [[String: Any]] {
    var entitlements: [[String: Any]] = []
    for await verification in Transaction.currentEntitlements {
      guard case .verified(let transaction) = verification,
        transaction.productType == .autoRenewable,
        transaction.revocationDate == nil
      else { continue }
      var map = transactionMap(transaction, jws: verification.jwsRepresentation)
      map["totalSeats"] = await totalSeats(for: transaction)
      map.merge(await renewalInfo(for: transaction)) { _, new in new }
      #if MULTISEAT_SDK
      if #available(iOS 27.3, *), let role = await groupRole(for: transaction) {
        map["groupRole"] = role
      }
      #endif
      entitlements.append(map)
    }
    return entitlements
  }

  /// Seats the group purchaser has in the current billing period.
  ///
  /// Adding seats creates a new transaction whose `purchasedQuantity` is
  /// only the seats added, with the same `originalID` and expiration date,
  /// and `currentEntitlements` returns just the newest one. So add up every
  /// unrevoked transaction in the period. The next renewal carries the full
  /// total again.
  private static func totalSeats(for current: Transaction) async -> Int {
    guard current.ownershipType == .purchased,
      let expiration = current.expirationDate
    else { return current.purchasedQuantity }
    var total = 0
    for await verification in Transaction.all {
      guard case .verified(let transaction) = verification,
        transaction.originalID == current.originalID,
        transaction.expirationDate == expiration,
        transaction.revocationDate == nil
      else { continue }
      total += transaction.purchasedQuantity
    }
    return max(total, current.purchasedQuantity)
  }

  /// What the subscription renews to. A downgrade to another plan in the
  /// group starts at the next renewal: the purchase returns the current
  /// transaction and only `autoRenewPreference` changes.
  private static func renewalInfo(for transaction: Transaction) async -> [String: Any] {
    guard let status = await transaction.subscriptionStatus,
      case .verified(let renewal) = status.renewalInfo
    else { return [:] }
    var info: [String: Any] = ["willAutoRenew": renewal.willAutoRenew]
    if let preference = renewal.autoRenewPreference {
      info["renewsToProductId"] = preference
    }
    #if MULTISEAT_SDK
    if #available(iOS 27.3, *), let renewalQuantity = renewal.renewalQuantity {
      info["renewalSeats"] = renewalQuantity
    }
    #endif
    return info
  }

  #if MULTISEAT_SDK
  /// `"purchaser"` or `"member"` of the group `transaction` belongs to, or
  /// `nil` when the App Store can't tell.
  ///
  /// `ownershipType` alone can't tell them apart: the group purchaser's own
  /// seat can arrive as an ASSIGNED copy of their purchase under another
  /// originalID. Only the group purchaser can be asked to share group
  /// information, so the data sharing consent eligibility answers it.
  @available(iOS 27.3, *)
  private static func groupRole(for transaction: Transaction) async -> String? {
    guard let multiSeat = transaction.multiSeatInfo else { return nil }
    if multiSeat.invitationManagement == .developer {
      // Developer-hosted invitations: members get no transaction.
      return transaction.ownershipType == .purchased ? "purchaser" : nil
    }

    // This transaction's subscription first, then the subscriptions this
    // account bought in the same group: the purchaser's ASSIGNED copy and
    // their PURCHASED transaction have different originalIDs.
    var originalIDs = [transaction.originalID]
    for await verification in Transaction.all {
      guard case .verified(let other) = verification,
        other.ownershipType == .purchased,
        other.subscriptionGroupID == transaction.subscriptionGroupID,
        !originalIDs.contains(other.originalID)
      else { continue }
      originalIDs.append(other.originalID)
    }

    var isMember = false
    for originalID in originalIDs {
      do {
        let eligibility = try await Product.SubscriptionInfo
          .multiSeatDataSharingConsentEligibility(originalTransactionID: originalID)
        switch eligibility {
        case .eligible:
          return "purchaser"
        case .ineligible(let reason):
          if reason == .alreadyConsented { return "purchaser" }
          if reason == .noOwnedActiveSubscription { isMember = true }
        @unknown default:
          break
        }
      } catch {
        // `unsupported` when not signed in to the App Store; try the next ID.
        continue
      }
    }
    return isMember ? "member" : nil
  }
  #endif

  private static func transactionMap(_ transaction: Transaction, jws: String) -> [String: Any] {
    var map: [String: Any] = [
      "transactionId": String(transaction.id),
      "originalId": String(transaction.originalID),
      "productId": transaction.productID,
      "subscriptionGroupId": transaction.subscriptionGroupID ?? "",
      // Seats bought by this transaction; see totalSeats(for:).
      "purchasedQuantity": transaction.purchasedQuantity,
      // PURCHASED, ASSIGNED or FAMILY_SHARED.
      "ownershipType": transaction.ownershipType.rawValue,
      "jws": jws,
      "purchaseDate": Int(transaction.purchaseDate.timeIntervalSince1970 * 1000),
    ]
    if let expirationDate = transaction.expirationDate {
      map["expirationDate"] = Int(expirationDate.timeIntervalSince1970 * 1000)
    }
    return map
  }

  // MARK: - Manage subscriptions

  /// Apple's sheet where the group purchaser invites members, removes them
  /// and changes the number of seats.
  @MainActor
  private static func showManageSubscriptions(viewController: UIViewController) async throws {
    guard let windowScene = viewController.view.window?.windowScene else {
      throw BridgeError(code: "NO_WINDOW_SCENE", message: "No window scene to present in.")
    }
    try await AppStore.showManageSubscriptions(in: windowScene)
  }
}
