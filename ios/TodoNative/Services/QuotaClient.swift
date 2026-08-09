import Foundation

// 与 workers/quota-proxy 契约对齐：
//   POST {base}/proxy/chat/completions — 转发 AI 请求（model 强制 deepseek-chat）
//   GET  {base}/proxy/quota          — 当前设备额度快照
//   POST {base}/proxy/register-pro   — 上传 StoreKit 交易 JWT 开通 Pro 额度
// 所有请求带 X-Device-Id（匿名设备 ID）。不引入第三方。

struct QuotaSnapshot: Decodable, Sendable {
    let freeUsed: Int
    let freeLimit: Int
    let proUsed: Int
    let proLimit: Int
    let isPro: Bool
    let today: String
}

enum QuotaError: LocalizedError, Sendable {
    case quotaExceeded(kind: String)
    case missingBaseURL
    case server(status: Int, code: String)

    var errorDescription: String? {
        switch self {
        case .quotaExceeded(let kind):
            switch kind {
            case "free":
                return Localization.t("quota.exceeded.free")
            case "daily":
                return Localization.t("quota.exceeded.daily")
            default:
                return Localization.t("quota.exceeded.other", kind)
            }
        case .missingBaseURL:
            return Localization.t("quota.missingBaseURL")
        case .server(let status, let code):
            return Localization.t("quota.server", status, code)
        }
    }
}

enum QuotaClient {
    static let baseURLKey = "quota_base_url"
    static let deviceIDKey = "device_id"

    // 测试注入口：默认共享会话
    nonisolated(unsafe) static var session: URLSession = .shared

    static var baseURL: String? {
        UserDefaults.standard.string(forKey: baseURLKey)
    }

    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey),
           !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: deviceIDKey)
        return newID
    }

    static func chat(body: [String: Any]) async throws -> [String: Any] {
        try await send(path: "/proxy/chat/completions", method: "POST", body: body)
    }

    static func quota() async throws -> QuotaSnapshot {
        let json = try await send(path: "/proxy/quota", method: "GET", body: nil)
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    static func registerPro(transactionJwt: String) async throws {
        _ = try await send(path: "/proxy/register-pro", method: "POST", body: ["transactionJwt": transactionJwt])
    }

    private static func send(path: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
        guard let base = baseURL,
              !base.isEmpty,
              let url = URL(string: "\(base.hasSuffix("/") ? String(base.dropLast()) : base)\(path)") else {
            throw QuotaError.missingBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-Id")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        guard (200..<300).contains(status) else {
            if status == 402 {
                let code = json["code"] as? String
                    ?? (json["error"] as? [String: Any])?["code"] as? String
                    ?? ""
                let kind = json["kind"] as? String
                    ?? (json["error"] as? [String: Any])?["kind"] as? String
                    ?? ""
                if code == "quota_exceeded" {
                    throw QuotaError.quotaExceeded(kind: kind)
                }
            }
            let code = json["code"] as? String
                ?? (json["error"] as? [String: Any])?["code"] as? String
                ?? "unknown"
            throw QuotaError.server(status: status, code: code)
        }
        return json
    }
}