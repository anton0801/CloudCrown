//
//  APIClient.swift
//  CloudCrown
//
//  Thin REST client for the CloudCrown API. Attaches the bearer token,
//  refreshes it once on a 401, and maps every failure to a typed APIError.
//

import Foundation

/// Supplies and refreshes the access token. Implemented by AuthService.
@MainActor
protocol AuthTokenProviding: AnyObject {
    func validAccessToken() async -> String?
    /// Attempts a refresh after a 401. Returns the new token, or nil when the
    /// session is unrecoverable.
    func refreshAccessToken() async -> String?
    func sessionDidExpire() async
}

enum HTTPMethod: String {
    case get = "GET", post = "POST", patch = "PATCH", delete = "DELETE"
}

@MainActor
final class APIClient {

    private let configuration: APIConfiguration
    private let session: URLSession
    weak var tokenProvider: AuthTokenProviding?

    private lazy var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private lazy var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            // Servers differ on fractional seconds; accept both.
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: text) { return date }
            if let date = ISO8601DateFormatter.plain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container,
                                                   debugDescription: "Unrecognised date: \(text)")
        }
        return d
    }()

    init(configuration: APIConfiguration = .current, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    var baseURL: URL { configuration.baseURL }

    // MARK: - Requests

    @discardableResult
    func send<Response: Decodable>(_ path: String,
                                   method: HTTPMethod = .get,
                                   body: Encodable? = nil,
                                   query: [String: String] = [:],
                                   authenticated: Bool = true,
                                   as type: Response.Type) async throws -> Response {
        let data = try await perform(path, method: method, body: body,
                                     query: query, authenticated: authenticated)
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func sendIgnoringResponse(_ path: String,
                              method: HTTPMethod = .post,
                              body: Encodable? = nil,
                              authenticated: Bool = true) async throws {
        _ = try await perform(path, method: method, body: body,
                              query: [:], authenticated: authenticated)
    }

    // MARK: - Core

    private func perform(_ path: String,
                         method: HTTPMethod,
                         body: Encodable?,
                         query: [String: String],
                         authenticated: Bool,
                         isRetry: Bool = false) async throws -> Data {

        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.server(status: -1, message: "Bad URL") }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = configuration.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        if authenticated {
            guard let token = await tokenProvider?.validAccessToken() else {
                throw APIError.notSignedIn
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw APIError.cancelled
            case .timedOut: throw APIError.timeout
            default: throw APIError.offline
            }
        } catch {
            throw APIError.offline
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1, message: "Malformed response")
        }

        if (200...299).contains(http.statusCode) { return data }

        // A single refresh attempt, then give up and end the session.
        if http.statusCode == 401, authenticated, !isRetry {
            if await tokenProvider?.refreshAccessToken() != nil {
                return try await perform(path, method: method, body: body,
                                         query: query, authenticated: authenticated, isRetry: true)
            }
            await tokenProvider?.sessionDidExpire()
            throw APIError.unauthorized
        }

        if http.statusCode == 429 {
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Int.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        }

        throw APIError.from(status: http.statusCode, body: data)
    }

    private static let userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "CloudCrown/\(version) (\(build); iOS)"
    }()
}

// MARK: - Helpers

struct EmptyResponse: Decodable {}

/// Lets `Encodable` existentials be encoded without generics leaking upward.
struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) {
        encodeClosure = { encoder in try wrapped.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}

extension ISO8601DateFormatter {
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
