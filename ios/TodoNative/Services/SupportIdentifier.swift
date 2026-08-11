import Foundation

enum SupportIdentifier {
    private static let prefix = "TD-"

    static func displayValue(for deviceID: String) -> String {
        prefix + deviceID
    }

    static func deviceID(from supportID: String) -> String? {
        guard supportID.hasPrefix(prefix) else { return nil }
        let candidate = String(supportID.dropFirst(prefix.count))
        guard UUID(uuidString: candidate) != nil else { return nil }
        return candidate
    }
}
