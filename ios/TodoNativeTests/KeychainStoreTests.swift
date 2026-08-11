import XCTest
@testable import TodoNative

private final class FakeKeychainBackend: KeychainPersisting {
    enum Failure: Error {
        case writeDenied
    }

    private(set) var values: [String: Data] = [:]
    var writeError: Error?

    func data(service: String, account: String) throws -> Data? {
        values["\(service)|\(account)"]
    }

    func setData(_ data: Data, service: String, account: String) throws {
        if let writeError {
            throw writeError
        }
        values["\(service)|\(account)"] = data
    }

    func deleteData(service: String, account: String) throws {
        values.removeValue(forKey: "\(service)|\(account)")
    }
}

final class KeychainStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "KeychainStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = ""
        super.tearDown()
    }

    func testWriteTrimsValueAndReadReturnsIt() throws {
        let backend = FakeKeychainBackend()
        let store = makeStore(backend: backend)

        try store.write("  sk-test-value\n")

        XCTAssertEqual(try store.read(), "sk-test-value")
    }

    func testWritingWhitespaceDeletesExistingValue() throws {
        let backend = FakeKeychainBackend()
        let store = makeStore(backend: backend)
        try store.write("sk-existing")

        try store.write(" \n ")

        XCTAssertNil(try store.read())
    }

    func testDeleteRemovesValue() throws {
        let backend = FakeKeychainBackend()
        let store = makeStore(backend: backend)
        try store.write("sk-existing")

        try store.delete()

        XCTAssertNil(try store.read())
    }

    func testLegacyUserDefaultsValueMigratesToKeychainAndIsRemoved() throws {
        let backend = FakeKeychainBackend()
        let store = makeStore(backend: backend)
        defaults.set("  sk-legacy  ", forKey: "openai_api_key")

        let value = try store.readMigratingLegacyValue(
            from: defaults,
            legacyKey: "openai_api_key"
        )

        XCTAssertEqual(value, "sk-legacy")
        XCTAssertEqual(try store.read(), "sk-legacy")
        XCTAssertNil(defaults.object(forKey: "openai_api_key"))
    }

    func testLegacyValueIsRetainedWhenKeychainWriteFails() {
        let backend = FakeKeychainBackend()
        backend.writeError = FakeKeychainBackend.Failure.writeDenied
        let store = makeStore(backend: backend)
        defaults.set("sk-must-survive", forKey: "openai_api_key")

        XCTAssertThrowsError(
            try store.readMigratingLegacyValue(
                from: defaults,
                legacyKey: "openai_api_key"
            )
        )

        XCTAssertEqual(defaults.string(forKey: "openai_api_key"), "sk-must-survive")
    }

    private func makeStore(backend: FakeKeychainBackend) -> KeychainStore {
        KeychainStore(
            service: "com.zhili.todo-native.credentials",
            account: "openai-api-key",
            backend: backend
        )
    }
}
