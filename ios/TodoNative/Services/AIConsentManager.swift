import Foundation

enum AIConsentRouteKind: Equatable, Sendable {
    case managed
    case bringYourOwnKey
}

struct AIConsentRoute: Identifiable, Equatable, Sendable {
    let identifier: String
    let recipientName: String
    let kind: AIConsentRouteKind

    init(
        identifier: String,
        recipientName: String,
        kind: AIConsentRouteKind? = nil
    ) {
        self.identifier = identifier
        self.recipientName = recipientName
        self.kind = kind ?? (identifier.hasPrefix("managed:") ? .managed : .bringYourOwnKey)
    }

    var id: String { identifier }
}

enum AIConsentDecision: Equatable, Sendable {
    case allowed
    case needsConsent
    case declined
}

enum RemoteAIConsentError: Error, Equatable, Sendable {
    case needsConsent(AIConsentRoute)
    case declined(AIConsentRoute)
}

enum AIConsentOutcome: Equatable, Sendable {
    case accepted
    case declined
}

struct AIConsentResolution: Identifiable, Equatable, Sendable {
    let id = UUID()
    let route: AIConsentRoute
    let outcome: AIConsentOutcome
}

@MainActor
final class AIConsentManager: ObservableObject {
    static let defaultStorageKey = "ai_remote_consent"

    private struct Record: Codable, Equatable {
        let version: String
        let routeIdentifier: String
        let timestamp: Date
    }

    let consentVersion: String?
    @Published private(set) var pendingRoute: AIConsentRoute?
    @Published private(set) var resolution: AIConsentResolution?
    private let storage: UserDefaults
    private let storageKey: String
    private var declinedRouteIdentifier: String?

    init(
        configuration: AppConfiguration = AppConfiguration(),
        storage: UserDefaults = .standard,
        storageKey: String = AIConsentManager.defaultStorageKey
    ) {
        self.consentVersion = configuration.aiConsentVersion
        self.storage = storage
        self.storageKey = storageKey
    }

    init(
        consentVersion: String?,
        storage: UserDefaults = .standard,
        storageKey: String = AIConsentManager.defaultStorageKey
    ) {
        let trimmedVersion = consentVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.consentVersion = trimmedVersion?.isEmpty == false ? trimmedVersion : nil
        self.storage = storage
        self.storageKey = storageKey
    }

    func decision(for route: AIConsentRoute) -> AIConsentDecision {
        if declinedRouteIdentifier == route.identifier {
            return .declined
        }
        guard let consentVersion,
              let record = storedRecord,
              record.version == consentVersion,
              record.routeIdentifier == route.identifier else {
            return .needsConsent
        }
        return .allowed
    }

    func accept(_ route: AIConsentRoute, at date: Date = Date()) {
        guard let consentVersion else { return }
        let record = Record(
            version: consentVersion,
            routeIdentifier: route.identifier,
            timestamp: date
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        storage.set(data, forKey: storageKey)
        declinedRouteIdentifier = nil
    }

    func decline(_ route: AIConsentRoute) {
        declinedRouteIdentifier = route.identifier
    }

    func revoke() {
        storage.removeObject(forKey: storageKey)
        declinedRouteIdentifier = nil
        pendingRoute = nil
        resolution = nil
    }

    func requestConsent(for route: AIConsentRoute) {
        guard decision(for: route) == .needsConsent else { return }
        resolution = nil
        pendingRoute = route
    }

    func acceptPendingConsent(at date: Date = Date()) {
        guard let route = pendingRoute else { return }
        accept(route, at: date)
        pendingRoute = nil
        resolution = AIConsentResolution(route: route, outcome: .accepted)
    }

    func declinePendingConsent() {
        guard let route = pendingRoute else { return }
        decline(route)
        pendingRoute = nil
        resolution = AIConsentResolution(route: route, outcome: .declined)
    }

    var hasStoredConsent: Bool {
        storedRecord != nil
    }

    private var storedRecord: Record? {
        guard let data = storage.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }
}

@MainActor
struct RemoteAIGate {
    let consentManager: AIConsentManager

    func perform<Value>(
        for route: AIConsentRoute,
        operation: () async throws -> Value
    ) async throws -> Value {
        switch consentManager.decision(for: route) {
        case .allowed:
            return try await operation()
        case .needsConsent:
            throw RemoteAIConsentError.needsConsent(route)
        case .declined:
            throw RemoteAIConsentError.declined(route)
        }
    }
}
