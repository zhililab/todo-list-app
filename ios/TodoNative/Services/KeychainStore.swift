import Foundation
import Security

protocol KeychainPersisting {
    func data(service: String, account: String) throws -> Data?
    func setData(_ data: Data, service: String, account: String) throws
    func deleteData(service: String, account: String) throws
}

enum KeychainStoreError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case invalidUTF8
}

struct SystemKeychainBackend: KeychainPersisting {
    func data(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    func setData(_ data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func deleteData(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainStore {
    static let defaultAccount = "openai-api-key"

    let service: String
    let account: String
    private let backend: any KeychainPersisting

    init(
        bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.zhili.todo-native",
        backend: any KeychainPersisting = SystemKeychainBackend()
    ) {
        self.init(
            service: "\(bundleIdentifier).credentials",
            account: Self.defaultAccount,
            backend: backend
        )
    }

    init(
        service: String,
        account: String,
        backend: any KeychainPersisting
    ) {
        self.service = service
        self.account = account
        self.backend = backend
    }

    func read() throws -> String? {
        guard let data = try backend.data(service: service, account: account) else {
            return nil
        }
        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidUTF8
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func write(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try delete()
            return
        }
        try backend.setData(Data(trimmed.utf8), service: service, account: account)
    }

    func delete() throws {
        try backend.deleteData(service: service, account: account)
    }

    func readMigratingLegacyValue(
        from defaults: UserDefaults,
        legacyKey: String
    ) throws -> String {
        let currentValue = try read()
        guard let legacyValue = defaults.string(forKey: legacyKey) else {
            return currentValue ?? ""
        }

        let trimmedLegacyValue = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLegacyValue.isEmpty else {
            defaults.removeObject(forKey: legacyKey)
            return currentValue ?? ""
        }

        let valueToKeep = currentValue ?? trimmedLegacyValue
        try write(valueToKeep)
        defaults.removeObject(forKey: legacyKey)
        return valueToKeep
    }
}
