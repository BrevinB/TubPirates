import Foundation
import Observation
import RevenueCat

/// A purchasable doubloon bundle, joined from RevenueCat's offering and our
/// product-ID → coins table.
struct CoinPack: Identifiable {
    let id: String
    let name: String
    let coins: Int
    let priceString: String
    let package: Package
}

/// RevenueCat wrapper for the doubloon coin packs (consumable IAP).
///
/// Safe-by-default: with no API key set, the service never configures, the
/// shop shows its "merchant is asleep" state, and the rest of the game is
/// untouched. Paste the key and the store lights up.
@MainActor
@Observable
final class StoreService: NSObject {
    static let shared = StoreService()

    /// RevenueCat public Apple API key (starts with `appl_`). Leave empty to
    /// disable the store entirely (development builds).
    static let apiKey = "appl_CehpLBBborFwXJaGdLRcqufLfqP"

    /// Product ID → doubloons granted. Must match the consumable IAPs in
    /// App Store Connect and the packages attached in RevenueCat.
    static let coinAmounts: [String: Int] = [
        "co.brevinb.TubPirates.doubloons.handful": 600,
        "co.brevinb.TubPirates.doubloons.chest": 2000,
        "co.brevinb.TubPirates.doubloons.hoard": 5000,
    ]

    /// Display names, pirate-flavored, keyed by product ID.
    static let packNames: [String: String] = [
        "co.brevinb.TubPirates.doubloons.handful": "Handful o' Doubloons",
        "co.brevinb.TubPirates.doubloons.chest": "Chest o' Doubloons",
        "co.brevinb.TubPirates.doubloons.hoard": "Hoard o' Doubloons",
    ]

    private(set) var isConfigured = false
    private(set) var packs: [CoinPack] = []
    private(set) var isLoading = false
    /// The last offerings load failed — the shop shows a retry state instead
    /// of pretending the store doesn't exist yet.
    private(set) var loadFailed = false

    /// How a purchase attempt ended. A cancel is silent; a failure is shown.
    enum PurchaseOutcome {
        case success(coins: Int)
        case cancelled
        case failed(message: String)
    }

    /// Called with the doubloon total each time new purchases are credited
    /// (wired to ProfileStore.award at app start). Kept as a callback so this
    /// singleton never has to reach into the SwiftUI environment.
    var onCoinsCredited: ((Int) -> Void)?

    private override init() {}

    /// Call once at app start. No-ops without an API key.
    func configureIfPossible() {
        guard !isConfigured, !Self.apiKey.isEmpty else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        Task {
            await loadOfferings()
            // Pick up purchases the shop's buy flow never saw: offer codes
            // redeemed in the App Store, or purchases that completed after
            // a crash mid-flow.
            await refreshPurchases()
        }
    }

    func loadOfferings() async {
        guard isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let offerings = try await Purchases.shared.offerings()
            let packages = offerings.current?.availablePackages ?? []
            packs = packages.compactMap { package in
                let productID = package.storeProduct.productIdentifier
                guard let coins = Self.coinAmounts[productID] else { return nil }
                return CoinPack(
                    id: productID,
                    name: Self.packNames[productID] ?? package.storeProduct.localizedTitle,
                    coins: coins,
                    priceString: package.storeProduct.localizedPriceString,
                    package: package
                )
            }
            .sorted { $0.coins < $1.coins }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Runs the purchase flow. A user cancel and a real failure are distinct —
    /// silently swallowing a failure reads as "I was charged and got nothing".
    func purchase(_ pack: CoinPack) async -> PurchaseOutcome {
        guard isConfigured else {
            return .failed(message: "The store isn't available right now.")
        }
        do {
            let result = try await Purchases.shared.purchase(package: pack.package)
            guard !result.userCancelled else { return .cancelled }
            // Crediting flows through the ledger like every other path, so a
            // delegate echo of this same transaction can't double-pay it.
            credit(from: result.customerInfo)
            return .success(coins: pack.coins)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Crediting (all purchase paths funnel through here)

    /// Transaction IDs already paid out, persisted outside the profile so
    /// "Reset Profile" can't re-credit old purchases.
    private static let creditedLedgerKey = "creditedStoreTransactionIDs"

    private var creditedTransactionIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.creditedLedgerKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.creditedLedgerKey) }
    }

    /// Pays out any doubloon purchase RevenueCat knows about that the ledger
    /// hasn't seen — the shop's own buys, App Store offer-code redemptions,
    /// whatever. Returns the doubloons granted (0 when nothing was new).
    @discardableResult
    private func credit(from info: CustomerInfo) -> Int {
        var credited = creditedTransactionIDs
        var granted = 0
        for transaction in info.nonSubscriptions {
            guard let coins = Self.coinAmounts[transaction.productIdentifier],
                  !credited.contains(transaction.transactionIdentifier)
            else { continue }
            credited.insert(transaction.transactionIdentifier)
            granted += coins
        }
        guard granted > 0 else { return 0 }
        creditedTransactionIDs = credited
        onCoinsCredited?(granted)
        return granted
    }

    /// Reconciles against RevenueCat's latest record of this user.
    func refreshPurchases() async {
        guard isConfigured else { return }
        guard let info = try? await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent) else { return }
        credit(from: info)
    }

    /// After the in-app redemption sheet closes: force a receipt sync so the
    /// just-redeemed code is visible immediately, then credit it. Returns the
    /// doubloons granted so the shop can celebrate with the right number.
    func creditAfterRedemption() async -> Int {
        guard isConfigured else { return 0 }
        guard let info = try? await Purchases.shared.syncPurchases() else { return 0 }
        return credit(from: info)
    }
}

// MARK: - RevenueCat delegate

extension StoreService: PurchasesDelegate {
    /// Fires whenever RevenueCat learns of new transactions — including ones
    /// that happened entirely outside the app (App Store code redemption).
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            self.credit(from: customerInfo)
        }
    }
}
