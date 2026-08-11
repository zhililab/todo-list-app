import Foundation

enum AppBuildMode: Equatable {
    case debug
    case release

    static var current: AppBuildMode {
#if DEBUG
        .debug
#else
        .release
#endif
    }
}

enum ManagedAIUnavailableReason: Equatable {
    case missingEndpoint
    case invalidEndpoint
}

enum ManagedAIAvailability: Equatable {
    case available(URL)
    case unavailable(ManagedAIUnavailableReason)
}

struct AppConfiguration {
    static let debugManagedAIBaseURLKey = "quota_base_url"

    private static let defaultPrivacyPolicyURL = URL(
        string: "https://todo-list-app.zhili1993.chatgpt.site/privacy.html"
    )!
    private static let defaultTermsOfUseURL = URL(
        string: "https://todo-list-app.zhili1993.chatgpt.site/terms.html"
    )!
    private static let defaultSupportURL = URL(
        string: "https://todo-list-app.zhili1993.chatgpt.site/support.html"
    )!

    private let infoDictionary: [String: Any]
    private let userDefaults: UserDefaults
    private let buildMode: AppBuildMode

    init(
        bundle: Bundle = .main,
        userDefaults: UserDefaults = .standard,
        buildMode: AppBuildMode = .current
    ) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            userDefaults: userDefaults,
            buildMode: buildMode
        )
    }

    init(
        infoDictionary: [String: Any],
        userDefaults: UserDefaults = .standard,
        buildMode: AppBuildMode = .current
    ) {
        self.infoDictionary = infoDictionary
        self.userDefaults = userDefaults
        self.buildMode = buildMode
    }

    var managedAIAvailability: ManagedAIAvailability {
        let configuredValue: Any?
        if buildMode == .debug,
           userDefaults.object(forKey: Self.debugManagedAIBaseURLKey) != nil {
            configuredValue = userDefaults.object(forKey: Self.debugManagedAIBaseURLKey)
        } else {
            configuredValue = infoDictionary["ManagedAIBaseURL"]
        }

        guard let configuredValue else {
            return .unavailable(.missingEndpoint)
        }
        guard let rawValue = configuredValue as? String else {
            return .unavailable(.invalidEndpoint)
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .unavailable(.missingEndpoint)
        }
        guard let url = Self.httpsURL(from: trimmed) else {
            return .unavailable(.invalidEndpoint)
        }
        return .available(url)
    }

    var managedAIBaseURL: URL? {
        guard case .available(let url) = managedAIAvailability else { return nil }
        return url
    }

    var privacyPolicyURL: URL? {
        legalURL(forKey: "PrivacyPolicyURL", fallback: Self.defaultPrivacyPolicyURL)
    }

    var termsOfUseURL: URL? {
        legalURL(forKey: "TermsOfUseURL", fallback: Self.defaultTermsOfUseURL)
    }

    var supportURL: URL? {
        legalURL(forKey: "SupportURL", fallback: Self.defaultSupportURL)
    }

    var aiConsentVersion: String? {
        guard let value = infoDictionary["AIConsentVersion"] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func legalURL(forKey key: String, fallback: URL) -> URL {
        guard let value = infoDictionary[key] as? String,
              let url = Self.httpsURL(from: value) else {
            return fallback
        }
        return url
    }

    private static func httpsURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            return nil
        }
        return components.url
    }
}
