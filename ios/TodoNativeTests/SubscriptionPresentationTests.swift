import XCTest
@testable import TodoNative

final class SubscriptionPresentationTests: XCTestCase {
    private let privacyURL = URL(string: "https://todo-list-app.zhili1993.chatgpt.site/privacy.html")!
    private let termsURL = URL(string: "https://todo-list-app.zhili1993.chatgpt.site/terms.html")!

    override func setUp() {
        super.setUp()
        Localization.setLanguage("en")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Localization.languageKey)
        super.tearDown()
    }

    func testRenewalCancellationAndLegalDisclosuresPrecedePurchaseButtons() throws {
        let order = PaywallPresentation.sectionOrder
        let products = try XCTUnwrap(order.firstIndex(of: .products))

        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .renewalAndCancellation)), products)
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .legalLinks)), products)
    }

    func testOnlyActiveProductPurchaseButtonIsDisabled() {
        let activeProductIDs: Set<String> = ["monthly"]

        XCTAssertTrue(PaywallPresentation.isPurchaseDisabled(
            productID: "monthly",
            activeProductIDs: activeProductIDs
        ))
        XCTAssertFalse(PaywallPresentation.isPurchaseDisabled(
            productID: "yearly",
            activeProductIDs: activeProductIDs
        ))
    }

    func testMonthlySubscriptionUsesStoreKitPriceAndBillingCycle() throws {
        let source = SubscriptionProductFacts(
            id: "com.zhili.todo.premium.monthly.v2",
            displayName: "Monthly Premium",
            displayPrice: "$4.99",
            subscriptionPeriod: .init(value: 1, unit: .month),
            introductoryOffer: nil
        )

        let presentation = try XCTUnwrap(
            SubscriptionPresentation(
                facts: source,
                isEligibleForIntroductoryOffer: false,
                privacyPolicyURL: privacyURL,
                termsOfUseURL: termsURL
            )
        )

        XCTAssertEqual(presentation.productID, source.id)
        XCTAssertEqual(presentation.displayPrice, "$4.99")
        XCTAssertEqual(presentation.billingPeriod, .init(value: 1, unit: .month))
        XCTAssertNil(presentation.introductoryOffer)
    }

    func testYearlySubscriptionPresentsOnlyEligibleStoreKitIntroductoryOffer() throws {
        let offer = SubscriptionOfferFacts(
            displayPrice: "$0.00",
            period: .init(value: 1, unit: .week),
            periodCount: 1,
            paymentMode: .freeTrial
        )
        let source = SubscriptionProductFacts(
            id: "com.zhili.todo.premium.yearly.v2",
            displayName: "Yearly Premium",
            displayPrice: "$39.99",
            subscriptionPeriod: .init(value: 1, unit: .year),
            introductoryOffer: offer
        )

        let eligible = try XCTUnwrap(
            SubscriptionPresentation(
                facts: source,
                isEligibleForIntroductoryOffer: true,
                privacyPolicyURL: privacyURL,
                termsOfUseURL: termsURL
            )
        )
        let ineligible = try XCTUnwrap(
            SubscriptionPresentation(
                facts: source,
                isEligibleForIntroductoryOffer: false,
                privacyPolicyURL: privacyURL,
                termsOfUseURL: termsURL
            )
        )

        XCTAssertEqual(eligible.billingPeriod, .init(value: 1, unit: .year))
        XCTAssertEqual(eligible.introductoryOffer, offer)
        XCTAssertNil(ineligible.introductoryOffer)
    }

    func testPresentationIncludesRenewalCancellationAndLegalFacts() throws {
        let presentation = try XCTUnwrap(
            SubscriptionPresentation(
                facts: .init(
                    id: "com.zhili.todo.premium.monthly.v2",
                    displayName: "Monthly Premium",
                    displayPrice: "¥4.99",
                    subscriptionPeriod: .init(value: 1, unit: .month),
                    introductoryOffer: nil
                ),
                isEligibleForIntroductoryOffer: false,
                privacyPolicyURL: privacyURL,
                termsOfUseURL: termsURL
            )
        )

        XCTAssertTrue(presentation.renewsAutomatically)
        XCTAssertEqual(presentation.cancellationRoute, .appStoreSubscriptions)
        XCTAssertEqual(presentation.privacyPolicyURL, privacyURL)
        XCTAssertEqual(presentation.termsOfUseURL, termsURL)
    }

    func testDeviceLocalSevenDayTrialDoesNotInventAppStoreIntroductoryOffer() throws {
        let presentation = try XCTUnwrap(
            SubscriptionPresentation(
                facts: .init(
                    id: "com.zhili.todo.premium.monthly.v2",
                    displayName: "Monthly Premium",
                    displayPrice: "$4.99",
                    subscriptionPeriod: .init(value: 1, unit: .month),
                    introductoryOffer: nil
                ),
                isEligibleForIntroductoryOffer: true,
                privacyPolicyURL: privacyURL,
                termsOfUseURL: termsURL
            )
        )

        XCTAssertNil(presentation.introductoryOffer, "The device-local seven-day experience is not a StoreKit offer")
    }

    func testNonSubscriptionProductHasNoSubscriptionPresentation() {
        let presentation = SubscriptionPresentation(
            facts: .init(
                id: "one-time",
                displayName: "One Time",
                displayPrice: "$1.99",
                subscriptionPeriod: nil,
                introductoryOffer: nil
            ),
            isEligibleForIntroductoryOffer: false,
            privacyPolicyURL: privacyURL,
            termsOfUseURL: termsURL
        )

        XCTAssertNil(presentation)
    }

    func testIntroductoryOfferPreservesPeriodCount() {
        let offer = SubscriptionOfferFacts(
            displayPrice: "$1.99",
            period: .init(value: 1, unit: .month),
            periodCount: 3,
            paymentMode: .payAsYouGo
        )

        XCTAssertEqual(offer.periodCount, 3)
    }

    func testFreeTrialCopyUsesTotalOfferDuration() {
        let offer = SubscriptionOfferFacts(
            displayPrice: "$0.00",
            period: .init(value: 1, unit: .week),
            periodCount: 2,
            paymentMode: .freeTrial
        )

        XCTAssertEqual(
            SubscriptionOfferPresentation(offer: offer).localizedDescription,
            "If eligible, introductory offer: 2 weeks free"
        )
    }

    func testPayAsYouGoCopyIncludesPricePerPeriodAndOfferDuration() {
        let offer = SubscriptionOfferFacts(
            displayPrice: "$1.99",
            period: .init(value: 1, unit: .month),
            periodCount: 3,
            paymentMode: .payAsYouGo
        )

        XCTAssertEqual(
            SubscriptionOfferPresentation(offer: offer).localizedDescription,
            "If eligible, introductory offer: $1.99 / month for 3 months"
        )
    }

    func testPayUpFrontCopyIncludesTotalOfferDurationWithoutPerPeriodClaim() {
        let offer = SubscriptionOfferFacts(
            displayPrice: "$4.99",
            period: .init(value: 1, unit: .month),
            periodCount: 3,
            paymentMode: .payUpFront
        )

        XCTAssertEqual(
            SubscriptionOfferPresentation(offer: offer).localizedDescription,
            "If eligible, introductory offer: $4.99 up front for 3 months"
        )
    }

    func testManagedRegistrationFailuresRemainVisibleAndRetryableInSettings() {
        let unavailable = ProRegistrationPresentation(status: .unavailable(.missingEndpoint))
        let failed = ProRegistrationPresentation(status: .failed)

        XCTAssertEqual(unavailable?.messageKey, "purchase.registrationUnavailable")
        XCTAssertTrue(try XCTUnwrap(unavailable).canRetry)
        XCTAssertEqual(failed?.messageKey, "purchase.registrationRetry")
        XCTAssertTrue(try XCTUnwrap(failed).canRetry)
    }
}
