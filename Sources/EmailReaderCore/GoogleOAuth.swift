import AppKit
import CryptoKit
import Foundation
import Network
import Security

public struct GoogleOAuthClient: Codable, Sendable {
    public static let canonicalAuthorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    public static let canonicalTokenEndpoint = "https://oauth2.googleapis.com/token"

    private static let allowedAuthorizationEndpoints: Set<String> = [
        canonicalAuthorizationEndpoint,
        "https://accounts.google.com/o/oauth2/auth"
    ]
    private static let allowedTokenEndpoints: Set<String> = [
        canonicalTokenEndpoint,
        "https://accounts.google.com/o/oauth2/token"
    ]

    public let clientID: String
    public let clientSecret: String
    public let authorizationEndpoint: String
    public let tokenEndpoint: String

    private struct Root: Decodable {
        struct Installed: Decodable {
            let clientID: String
            let clientSecret: String
            let authURI: String
            let tokenURI: String

            enum CodingKeys: String, CodingKey {
                case clientID = "client_id"
                case clientSecret = "client_secret"
                case authURI = "auth_uri"
                case tokenURI = "token_uri"
            }
        }
        let installed: Installed
    }

    public static func load(from url: URL) throws -> GoogleOAuthClient {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let root = try JSONDecoder().decode(Root.self, from: Data(contentsOf: url))
        guard !root.installed.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !root.installed.clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              allowedAuthorizationEndpoints.contains(root.installed.authURI),
              allowedTokenEndpoints.contains(root.installed.tokenURI) else {
            throw GoogleOAuthError.invalidConfiguration
        }
        return GoogleOAuthClient(
            clientID: root.installed.clientID,
            clientSecret: root.installed.clientSecret,
            authorizationEndpoint: canonicalAuthorizationEndpoint,
            tokenEndpoint: canonicalTokenEndpoint
        )
    }
}

public struct OAuthTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let expiresIn: Int
    public let refreshToken: String?
    public let scope: String?
    public let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

public enum GoogleOAuthError: Error, LocalizedError {
    case invalidConfiguration
    case listener(String)
    case authorizationDenied(String)
    case invalidResponse(String)
    case missingRefreshToken

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "OAuth 客户端 JSON 不是 Google Desktop app 配置。"
        case .listener(let message): "无法启动本地 OAuth 回调：\(message)"
        case .authorizationDenied(let message): "Google 授权未完成：\(message)"
        case .invalidResponse(let message): "Google OAuth 返回异常：\(message)"
        case .missingRefreshToken: "Google 没有返回 refresh token，请在账号安全设置中撤销旧授权后重试。"
        }
    }
}

public final class GoogleOAuthCoordinator: @unchecked Sendable {
    private let keychain: KeychainStore

    public init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    @MainActor
    public func authorize(configurationURL: URL, loginHint: String? = nil) async throws {
        let client: GoogleOAuthClient
        do { client = try GoogleOAuthClient.load(from: configurationURL) }
        catch { throw GoogleOAuthError.invalidConfiguration }

        let verifier = Self.randomVerifier()
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomVerifier(length: 32)
        let server = OAuthLoopbackServer(expectedState: state)
        let port = try await server.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        var components = URLComponents(string: client.authorizationEndpoint)
        var queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile https://www.googleapis.com/auth/gmail.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        if let loginHint, !loginHint.isEmpty {
            queryItems.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components?.queryItems = queryItems
        guard let authorizationURL = components?.url else { throw GoogleOAuthError.invalidConfiguration }
        NSWorkspace.shared.open(authorizationURL)

        let callback = try await server.waitForCallback()
        guard callback.state == state else { throw GoogleOAuthError.authorizationDenied("安全校验失败") }
        if let error = callback.error { throw GoogleOAuthError.authorizationDenied(error) }
        guard let code = callback.code else { throw GoogleOAuthError.authorizationDenied("缺少授权码") }

        let token = try await exchangeCode(code, client: client, redirectURI: redirectURI, verifier: verifier)
        guard let refresh = token.refreshToken else { throw GoogleOAuthError.missingRefreshToken }
        try keychain.setOAuthBundle(OAuthCredentialBundle(
            clientID: client.clientID,
            clientSecret: client.clientSecret,
            tokenEndpoint: client.tokenEndpoint,
            refreshToken: refresh,
            accessToken: token.accessToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn - 60)).timeIntervalSince1970
        ))
    }

    private func exchangeCode(_ code: String, client: GoogleOAuthClient, redirectURI: String, verifier: String) async throws -> OAuthTokenResponse {
        guard let url = URL(string: client.tokenEndpoint) else { throw GoogleOAuthError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "code": code,
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw GoogleOAuthError.invalidResponse(String(data: data, encoding: .utf8) ?? "HTTP error")
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let string = values.sorted(by: { $0.key < $1.key }).map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return Data(string.utf8)
    }

    private static func randomVerifier(length: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private final class OAuthLoopbackServer: @unchecked Sendable {
    struct Callback: Sendable { let code: String?; let state: String?; let error: String? }

    private let expectedState: String
    private let queue = DispatchQueue(label: "com.sota.EmailReader.oauth-loopback")
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private var callbackContinuation: CheckedContinuation<Callback, Error>?
    private var pendingCallback: Callback?
    private let lock = NSLock()

    init(expectedState: String) {
        self.expectedState = expectedState
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
            do {
                let parameters = NWParameters.tcp
                parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                let listener = try NWListener(using: parameters)
                self.listener = listener
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        if let port = self?.listener?.port?.rawValue {
                            self?.finishStart(.success(port))
                        }
                    case .failed(let error):
                        self?.finishStart(.failure(GoogleOAuthError.listener(error.localizedDescription)))
                    default: break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
            } catch {
                finishStart(.failure(error))
            }
        }
    }

    private func finishStart(_ result: Result<UInt16, Error>) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        guard let continuation else { return }
        switch result {
        case .success(let port): continuation.resume(returning: port)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }

    func waitForCallback() async throws -> Callback {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingCallback {
                self.pendingCallback = nil
                lock.unlock()
                continuation.resume(returning: pendingCallback)
            } else {
                callbackContinuation = continuation
                lock.unlock()
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8), let firstLine = request.split(separator: "\r\n").first else { return }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2,
                  parts[0] == "GET",
                  let url = URL(string: "http://127.0.0.1\(parts[1])"),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.path == "/" else {
                self.respond(connection, status: "400 Bad Request", message: "OAuth 回调无效，请返回 App 重试。")
                return
            }
            var items: [String: String] = [:]
            for item in components.queryItems ?? [] {
                guard items[item.name] == nil else {
                    self.respond(connection, status: "400 Bad Request", message: "OAuth 回调参数重复，请返回 App 重试。")
                    return
                }
                items[item.name] = item.value ?? ""
            }
            let callback = Callback(code: items["code"], state: items["state"], error: items["error"])
            guard callback.state == self.expectedState else {
                self.respond(connection, status: "400 Bad Request", message: "安全校验失败；原授权窗口仍可继续。")
                return
            }
            self.respond(connection, status: "200 OK", message: "Email Reader 已获得授权，可以关闭此页面并返回 App。")
            self.deliver(callback)
            self.listener?.cancel()
        }
    }

    private func respond(_ connection: NWConnection, status: String, message: String) {
        let html = "<html><body style='font-family:-apple-system;padding:48px'><h2>\(message)</h2></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func deliver(_ callback: Callback) {
        lock.lock()
        let continuation = callbackContinuation
        callbackContinuation = nil
        if continuation == nil { pendingCallback = callback }
        lock.unlock()
        continuation?.resume(returning: callback)
    }
}
