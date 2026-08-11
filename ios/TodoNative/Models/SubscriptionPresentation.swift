import Foundation
import StoreKit

struct SubscriptionPeriodFacts: Equatable, Sendable {
    enum Unit: Equatable, Sendable {
        case day
        case week
        case month
        case year
    }

    let value: Int
    let unit: Unit

    init(value: Int, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    init(_ period: Product.SubscriptionPeriod) {
        value = period.value
        switch period.unit {
        case .day: unit = .day
        case .week: unit = .week
        case .month: unit = .month
        case .year: unit = .year
        @unknown default: unit = .day
        }
    }
}

struct SubscriptionOfferFacts: Equatable, Sendable {
    enum PaymentMode: Equatable, Sendable {
        case payAsYouGo
        case payUpFront
        case freeTrial
        case unknown(String)
    }

    let displayPrice: String
    let period: SubscriptionPeriodFacts
    let periodCount: Int
    let paymentMode: PaymentMode

    init(
        displayPrice: String,
        period: SubscriptionPeriodFacts,
        periodCount: Int,
        paymentMode: PaymentMode
    ) {
        self.displayPrice = displayPrice
        self.period = period
        self.periodCount = periodCount
        self.paymentMode = paymentMode
    }

    init(_ offer: Product.SubscriptionOffer) {
        displayPrice = offer.displayPrice
        period = SubscriptionPeriodFacts(offer.period)
        periodCount = offer.periodCount
        switch offer.paymentMode {
        case .payAsYouGo: paymentMode = .payAsYouGo
        case .payUpFront: paymentMode = .payUpFront
        case .freeTrial: paymentMode = .freeTrial
        default: paymentMode = .unknown(offer.paymentMode.rawValue)
        }
    }
}

struct SubscriptionOfferPresentation: Equatable, Sendable {
    let offer: SubscriptionOfferFacts

    var localizedDescription: String {
        let perPeriod = Self.periodText(offer.period)
        let totalPeriod = Self.periodText(.init(
            value: offer.period.value * offer.periodCount,
            unit: offer.period.unit
        ))

        switch offer.paymentMode {
        case .freeTrial:
            return Localization.t("paywall.introFreeTrial", totalPeriod)
        case .payAsYouGo:
            return Localization.t("paywall.introPayAsYouGo", offer.displayPrice, perPeriod, totalPeriod)
        case .payUpFront:
            return Localization.t("paywall.introPayUpFront", offer.displayPrice, totalPeriod)
        case .unknown:
            return Localization.t("paywall.introPrice", offer.displayPrice, totalPeriod)
        }
    }

    static func periodText(_ period: SubscriptionPeriodFacts) -> String {
        let singular = period.value == 1
        let key: String
        switch period.unit {
        case .day: key = singular ? "paywall.period.day" : "paywall.period.days"
        case .week: key = singular ? "paywall.period.week" : "paywall.period.weeks"
        case .month: key = singular ? "paywall.period.month" : "paywall.period.months"
        case .year: key = singular ? "paywall.period.year" : "paywall.period.years"
        }
        return singular ? Localization.t(key) : Localization.t(key, period.value)
    }
}

enum PaywallSection: Hashable, Sendable {
    case header
    case renewalAndCancellation
    case legalLinks
    case products
    case status
    case billingActions
}

enum PaywallPresentation {
    static let sectionOrder: [PaywallSection] = [
        .header,
        .renewalAndCancellation,
        .legalLinks,
        .products,
        .status,
        .billingActions
    ]

    static func isPurchaseDisabled(productID: String, activeProductIDs: Set<String>) -> Bool {
        activeProductIDs.contains(productID)
    }
}

struct SubscriptionProductFacts: Equatable, Sendable {
    let id: String
    let displayName: String
    let displayPrice: String
    let subscriptionPeriod: SubscriptionPeriodFacts?
    let introductoryOffer: SubscriptionOfferFacts?

    init(
        id: String,
        displayName: String,
        displayPrice: String,
        subscriptionPeriod: SubscriptionPeriodFacts?,
        introductoryOffer: SubscriptionOfferFacts?
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.subscriptionPeriod = subscriptionPeriod
        self.introductoryOffer = introductoryOffer
    }

    init(product: Product) {
        id = product.id
        displayName = product.displayName
        displayPrice = product.displayPrice
        subscriptionPeriod = product.subscription.map { SubscriptionPeriodFacts($0.subscriptionPeriod) }
        introductoryOffer = product.subscription?.introductoryOffer.map(SubscriptionOfferFacts.init)
    }
}

struct SubscriptionPresentation: Equatable, Sendable {
    enum CancellationRoute: Equatable, Sendable {
        case appStoreSubscriptions
    }

    let productID: String
    let displayName: String
    let displayPrice: String
    let billingPeriod: SubscriptionPeriodFacts
    let introductoryOffer: SubscriptionOfferFacts?
    let renewsAutomatically: Bool
    let cancellationRoute: CancellationRoute
    let privacyPolicyURL: URL
    let termsOfUseURL: URL

    init?(
        facts: SubscriptionProductFacts,
        isEligibleForIntroductoryOffer: Bool,
        privacyPolicyURL: URL?,
        termsOfUseURL: URL?
    ) {
        guard let billingPeriod = facts.subscriptionPeriod,
              let privacyPolicyURL,
              let termsOfUseURL else {
            return nil
        }

        productID = facts.id
        displayName = facts.displayName
        displayPrice = facts.displayPrice
        self.billingPeriod = billingPeriod
        introductoryOffer = isEligibleForIntroductoryOffer ? facts.introductoryOffer : nil
        renewsAutomatically = true
        cancellationRoute = .appStoreSubscriptions
        self.privacyPolicyURL = privacyPolicyURL
        self.termsOfUseURL = termsOfUseURL
    }

    init?(
        product: Product,
        isEligibleForIntroductoryOffer: Bool,
        configuration: AppConfiguration
    ) {
        self.init(
            facts: SubscriptionProductFacts(product: product),
            isEligibleForIntroductoryOffer: isEligibleForIntroductoryOffer,
            privacyPolicyURL: configuration.privacyPolicyURL,
            termsOfUseURL: configuration.termsOfUseURL
        )
    }
}
