import Observation
import StoreKit

/// Loads the real subscription products from the App Store.
///
/// There are no hard-coded prices anywhere in this type or in the screen that
/// uses it. Every figure the user sees — price, period, trial length — comes
/// from StoreKit's own localised product data, which is the only way it can be
/// correct in every storefront.
///
/// When no products come back (nothing configured yet, or offline), the
/// activation screen simply presents itself without pricing rather than
/// inventing any. That is a deliberate trade: an honest screen with no numbers
/// beats a convincing screen with fake ones.
@Observable
@MainActor
final class SubscriptionStore {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable
    }

    private(set) var state: LoadState = .idle
    private(set) var products: [Product] = []
    private(set) var selectedID: String?
    private(set) var isPurchasing = false
    private(set) var isEntitled = false

    /// Product identifiers this app offers, in presentation order. These are
    /// configuration, not pricing — the price attached to each is whatever App
    /// Store Connect says it is.
    private static let productIDs: [String] = [
        "app.rork.gymlock.pro.yearly",
        "app.rork.gymlock.pro.monthly",
    ]

    var selectedProduct: Product? {
        products.first { $0.id == selectedID }
    }

    /// True once real, purchasable products are on hand.
    var hasProducts: Bool { !products.isEmpty }

    func load() async {
        guard state == .idle else { return }
        state = .loading

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            // Preserve the declared order rather than StoreKit's.
            products = Self.productIDs.compactMap { id in
                fetched.first { $0.id == id }
            }
            selectedID = products.first?.id
            state = products.isEmpty ? .unavailable : .loaded
        } catch {
            state = .unavailable
        }

        await refreshEntitlement()
    }

    func select(_ product: Product) {
        selectedID = product.id
        Haptics.tap()
    }

    /// Buys the selected product. Returns true when the user ends up entitled,
    /// including when the purchase was already active.
    func purchase() async -> Bool {
        guard let product = selectedProduct, !isPurchasing else { return false }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                guard case let .verified(transaction) = verification else { return false }
                await transaction.finish()
                isEntitled = true
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            return false
        }
    }

    func restore() async {
        // Fully qualified: this app has its own `AppStore` type, and an
        // unqualified reference would resolve to that one.
        try? await StoreKit.AppStore.sync()
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        for await entitlement in Transaction.currentEntitlements {
            guard case let .verified(transaction) = entitlement else { continue }
            if Self.productIDs.contains(transaction.productID) {
                isEntitled = true
                return
            }
        }
        isEntitled = false
    }
}

// MARK: - Display helpers

extension Product {
    /// "per month", "per year", and so on, taken from the product's own period.
    var periodDescription: String {
        guard let period = subscription?.subscriptionPeriod else { return "" }

        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: unit = "period"
        }

        return period.value == 1 ? "per \(unit)" : "per \(period.value) \(unit)s"
    }

    /// The real introductory offer, described in the offer's own terms, or nil
    /// when the product has none.
    var introductoryOfferDescription: String? {
        guard let offer = subscription?.introductoryOffer else { return nil }

        let unit: String
        switch offer.period.unit {
        case .day: unit = offer.period.value == 1 ? "day" : "days"
        case .week: unit = offer.period.value == 1 ? "week" : "weeks"
        case .month: unit = offer.period.value == 1 ? "month" : "months"
        case .year: unit = offer.period.value == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }

        let length = "\(offer.period.value) \(unit)"

        switch offer.paymentMode {
        case .freeTrial: return "\(length) free"
        case .payAsYouGo: return "\(offer.displayPrice) \(unit) for \(length)"
        case .payUpFront: return "\(offer.displayPrice) for the first \(length)"
        default: return nil
        }
    }

    /// True when the introductory offer is an actual free trial, which is the
    /// only case where the CTA is allowed to say "free trial".
    var hasFreeTrial: Bool {
        subscription?.introductoryOffer?.paymentMode == .freeTrial
    }
}
