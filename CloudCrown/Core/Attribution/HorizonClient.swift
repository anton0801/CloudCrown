import Foundation

struct HorizonOutcome {
    var authorized: Bool
    var analyticsURL: URL?
    var message: String?

    static let empty = HorizonOutcome(authorized: false, analyticsURL: nil, message: nil)
}

actor HorizonClient {

    private let baseURL: URL
    private let session: URLSession

    init(configuration: APIConfiguration = .current) {
        self.baseURL = configuration.baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    @discardableResult
    func observe(_ fields: [String: Any]) async -> Bool {
        do {
            _ = try await send("horizon/observe", fields)
            return true
        } catch {
            return false
        }
    }

    func resolve(_ fields: [String: Any]) async -> HorizonOutcome {
        do {
            let (data, response) = try await send("horizon/resolve", fields)
            let header = response.value(forHTTPHeaderField: "analytics-service")
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            return HorizonOutcome(
                authorized: object?["authorized"] as? Bool ?? false,
                analyticsURL: header.flatMap { URL(string: $0) },
                message: object?["message"] as? String
            )
        } catch {
            return .empty
        }
    }

    @discardableResult
    func link(anchor: String, accessToken: String) async -> Bool {
        do {
            _ = try await send("horizon/link", ["anchor": anchor], bearer: accessToken)
            return true
        } catch {
            return false
        }
    }

    private func send(_ path: String,
                      _ fields: [String: Any],
                      bearer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        let body = try PayloadCrypto.envelope(fields.compactMapValues { $0 })
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer = bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.init(rawValue: http.statusCode))
        }
        return (data, http)
    }
}
