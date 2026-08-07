import Foundation

public enum GmailClientError: Error, LocalizedError {
    case notAuthorized
    case invalidURL
    case http(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: "Gmail 尚未授权。"
        case .invalidURL: "Gmail API 地址无效。"
        case .http(let status, let body): "Gmail API 请求失败（\(status)）：\(body)"
        }
    }

    public var statusCode: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}

public actor GoogleTokenProvider {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    public func accessToken() async throws -> String {
        guard var credentials = try keychain.oauthBundle() else {
            throw GmailClientError.notAuthorized
        }
        if Date().timeIntervalSince1970 < credentials.expiresAt { return credentials.accessToken }
        guard let url = URL(string: credentials.tokenEndpoint) else { throw GmailClientError.notAuthorized }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleOAuthCoordinator.formBody([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token"
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GmailClientError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
        let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        credentials.accessToken = token.accessToken
        credentials.expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn - 60)).timeIntervalSince1970
        try keychain.setOAuthBundle(credentials)
        return token.accessToken
    }
}

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String
    public let historyId: String
}

public struct GmailThreadReference: Decodable, Sendable {
    public let id: String
    public let historyId: String?
}

public struct GmailThreadList: Decodable, Sendable {
    public let threads: [GmailThreadReference]?
    public let nextPageToken: String?
}

public struct GmailHistoryList: Decodable, Sendable {
    public struct History: Decodable, Sendable {
        public struct MessageAdded: Decodable, Sendable {
            public struct Message: Decodable, Sendable { public let id: String; public let threadId: String }
            public let message: Message
        }
        public struct Message: Decodable, Sendable { public let id: String; public let threadId: String }
        public let messages: [Message]?
        public let messagesAdded: [MessageAdded]?
    }
    public let history: [History]?
    public let historyId: String?
    public let nextPageToken: String?
}

public struct GmailThreadPayload: Decodable, Sendable {
    public struct Message: Decodable, Sendable {
        public struct Payload: Decodable, Sendable {
            public struct Header: Decodable, Sendable { public let name: String; public let value: String }
            public struct Body: Decodable, Sendable { public let size: Int?; public let data: String?; public let attachmentId: String? }
            public let mimeType: String?
            public let filename: String?
            public let headers: [Header]?
            public let body: Body?
            public let parts: [Payload]?
        }
        public let id: String
        public let threadId: String
        public let labelIds: [String]?
        public let snippet: String?
        public let internalDate: String?
        public let payload: Payload?
    }
    public let id: String
    public let historyId: String?
    public let messages: [Message]
}

public actor GmailClient {
    private let tokenProvider: GoogleTokenProvider
    private let baseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    public init(tokenProvider: GoogleTokenProvider = GoogleTokenProvider()) {
        self.tokenProvider = tokenProvider
    }

    public func profile() async throws -> GmailProfile {
        try await get(path: "/profile", query: [], as: GmailProfile.self)
    }

    public func listRecentThreadIDs(days: Int = 30, limit: Int = 50) async throws -> [String] {
        var result: [String] = []
        var token: String?
        repeat {
            var query = [
                URLQueryItem(name: "q", value: "in:inbox newer_than:\(days)d -in:spam -in:trash"),
                URLQueryItem(name: "maxResults", value: String(min(100, limit - result.count)))
            ]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let page: GmailThreadList = try await get(path: "/threads", query: query, as: GmailThreadList.self)
            result.append(contentsOf: (page.threads ?? []).map(\.id))
            token = page.nextPageToken
        } while token != nil && result.count < limit
        return Array(result.prefix(limit))
    }

    public func changedThreadIDs(since historyID: String) async throws -> [String] {
        var ids = Set<String>()
        var token: String?
        repeat {
            var query = [
                URLQueryItem(name: "startHistoryId", value: historyID),
                URLQueryItem(name: "labelId", value: "INBOX"),
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
            let page: GmailHistoryList = try await get(path: "/history", query: query, as: GmailHistoryList.self)
            for item in page.history ?? [] {
                for message in item.messages ?? [] { ids.insert(message.threadId) }
                for added in item.messagesAdded ?? [] { ids.insert(added.message.threadId) }
            }
            token = page.nextPageToken
        } while token != nil
        return Array(ids)
    }

    public func thread(id: String) async throws -> GmailThreadPayload {
        try await get(path: "/threads/\(id)", query: [URLQueryItem(name: "format", value: "full")], as: GmailThreadPayload.self)
    }

    private func get<T: Decodable & Sendable>(path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        guard var components = URLComponents(string: baseURL + path) else { throw GmailClientError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw GmailClientError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await tokenProvider.accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GmailClientError.http((response as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
