import XCTest
@testable import TodoNative

// Mock URLProtocol：拦截 URLSession 请求返回预设响应
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
final class QuotaClientTests: XCTestCase {
    private let baseURLKey = "quota_base_url"
    private let deviceIDKey = "device_id"

    private var mockSession: URLSession!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: deviceIDKey)
        MockURLProtocol.handler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        QuotaClient.session = mockSession
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: baseURLKey)
        UserDefaults.standard.removeObject(forKey: deviceIDKey)
        MockURLProtocol.handler = nil
        QuotaClient.session = .shared
        super.tearDown()
    }

    private static func jsonResponse(_ status: Int, _ object: [String: Any]) -> (HTTPURLResponse, Data) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: URL(string: "https://quota.test/proxy/quota")!,
                                       statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, data)
    }

    func testMissingBaseURLThrows() async {
        do {
            _ = try await QuotaClient.quota()
            XCTFail("should throw")
        } catch QuotaError.missingBaseURL {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testQuotaSuccessDecodesSnapshot() async throws {
        UserDefaults.standard.set("https://quota.test", forKey: baseURLKey)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/proxy/quota")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Device-Id"), QuotaClient.deviceID)
            return Self.jsonResponse(200, [
                "freeUsed": 3, "freeLimit": 10, "proUsed": 0, "proLimit": 20,
                "isPro": false, "today": "2026-08-09"
            ])
        }
        let snapshot = try await QuotaClient.quota()
        XCTAssertEqual(snapshot.freeUsed, 3)
        XCTAssertEqual(snapshot.freeLimit, 10)
        XCTAssertEqual(snapshot.proLimit, 20)
        XCTAssertFalse(snapshot.isPro)
        XCTAssertEqual(snapshot.today, "2026-08-09")
    }

    func testQuotaExceededFree402() async {
        UserDefaults.standard.set("https://quota.test", forKey: baseURLKey)
        MockURLProtocol.handler = { _ in
            Self.jsonResponse(402, ["error": ["code": "quota_exceeded", "kind": "free"]])
        }
        do {
            _ = try await QuotaClient.chat(body: ["model": "deepseek-chat", "messages": []])
            XCTFail("should throw")
        } catch QuotaError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, "free")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testQuotaExceededDaily402FlatKind() async {
        UserDefaults.standard.set("https://quota.test", forKey: baseURLKey)
        MockURLProtocol.handler = { _ in
            Self.jsonResponse(402, ["code": "quota_exceeded", "kind": "daily"])
        }
        do {
            _ = try await QuotaClient.chat(body: [:])
            XCTFail("should throw")
        } catch QuotaError.quotaExceeded(let kind) {
            XCTAssertEqual(kind, "daily")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testServerError500SurfacesStatusCodeAndCode() async {
        UserDefaults.standard.set("https://quota.test", forKey: baseURLKey)
        MockURLProtocol.handler = { _ in
            Self.jsonResponse(500, ["error": ["code": "upstream_failure"]])
        }
        do {
            _ = try await QuotaClient.chat(body: [:])
            XCTFail("should throw")
        } catch QuotaError.server(let status, let code) {
            XCTAssertEqual(status, 500)
            XCTAssertEqual(code, "upstream_failure")
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRegisterProPostsTransactionJwt() async throws {
        UserDefaults.standard.set("https://quota.test", forKey: baseURLKey)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/proxy/register-pro")
            let data = request.httpBody ?? Self.bodyData(from: request)
            let body = try! JSONSerialization.jsonObject(with: data) as! [String: String]
            XCTAssertEqual(body["transactionJwt"], "jwt-abc")
            return Self.jsonResponse(200, ["isPro": true])
        }
        try await QuotaClient.registerPro(transactionJwt: "jwt-abc")
    }

    private static func bodyData(from request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }

    func testDeviceIDPersistsAcrossCalls() {
        let first = QuotaClient.deviceID
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(QuotaClient.deviceID, first)
        XCTAssertEqual(UserDefaults.standard.string(forKey: deviceIDKey), first)
    }

    func testBaseURLTrailingSlashNormalized() async throws {
        UserDefaults.standard.set("https://quota.test/", forKey: baseURLKey)
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://quota.test/proxy/quota")
            return Self.jsonResponse(200, [
                "freeUsed": 0, "freeLimit": 10, "proUsed": 0, "proLimit": 20,
                "isPro": false, "today": "2026-08-09"
            ])
        }
        _ = try await QuotaClient.quota()
    }
}
