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
final class StoreService {
    static let shared = StoreService()

    /// RevenueCat public Apple API key (starts with `appl_`). Leave empty to
    /// disable the store entirely (development builds).
    /// TODO: paste from RevenueCat dashboard → Project → API keys.
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
    private(set) var lastError: String?

    private init() {}

    /// Call once at app start. No-ops without an API key.
    func configureIfPossible() {
        guard !isConfigured, !Self.apiKey.isEmpty else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: Self.apiKey)
        isConfigured = true
        Task { await loadOfferings() }
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
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Runs the purchase flow. Returns the doubloons to grant on success,
    /// nil when cancelled or failed (lastError set on failure).
    func purchase(_ pack: CoinPack) async -> Int? {
        guard isConfigured else { return nil }
        do {
            let result = try await Purchases.shared.purchase(package: pack.package)
            guard !result.userCancelled else { return nil }
            return pack.coins
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}
