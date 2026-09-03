//
//  APIError.swift
//  CloudCrown
//
//  Every failure the API layer can produce, in language a screen can show
//  directly. Nothing is reported as success when it was not.
//

import Foundation

/// Machine-readable error body returned by the server.
struct APIErrorBody: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
        let fields: [String: String]?
    }
    let error: Payload
}

enum APIError: LocalizedError, Equatable {
    case offline
    case timeout
    case cancelled
    /// 400/422 with per-field messages, so a form can mark the right input.
    case validation(message: String, fields: [String: String])
    case invalidCredentials
    case emailAlreadyRegistered
    case unauthorized
    case forbidden
    case notFound
    case conflict(String)
    case rateLimited(retryAfter: Int?)
    case server(status: Int, message: String)
    case decoding(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .offline:
            return "No connection to the CloudCrown server."
        case .timeout:
            return "The server took too long to respond."
        case .cancelled:
            return "The request was cancelled."
        case .validation(let message, _):
            return message
        case .invalidCredentials:
            return "That email and password do not match an account."
        case .emailAlreadyRegistered:
            return "An account already exists for this email."
        case .unauthorized:
            return "Your session expired. Sign in again to continue."
        case .forbidden:
            return "This account is not allowed to perform that action."
        case .notFound:
            return "The server could not find what was requested."
        case .conflict(let message):
            return message
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Too many attempts. Try again in \(retryAfter) seconds."
            }
            return "Too many attempts. Try again shortly."
        case .server(let status, let message):
            return message.isEmpty ? "The server replied with status \(status)." : message
        case .decoding(let detail):
            return "The server response could not be read. \(detail)"
        case .notSignedIn:
            return "You are not signed in."
        }
    }

    var isOffline: Bool { self == .offline || self == .timeout }

    /// A session that can be recovered by refreshing or re-authenticating.
    var requiresReauthentication: Bool { self == .unauthorized }

    func fieldMessage(_ field: String) -> String? {
        if case .validation(_, let fields) = self { return fields[field] }
        return nil
    }

    static func from(status: Int, body: Data) -> APIError {
        let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: body)
        let code = decoded?.error.code ?? ""
        let message = decoded?.error.message ?? ""
        let fields = decoded?.error.fields ?? [:]

        switch code {
        case "invalid_credentials": return .invalidCredentials
        case "email_already_registered": return .emailAlreadyRegistered
        case "validation_failed":
            return .validation(message: message.isEmpty ? "Please check the highlighted fields." : message,
                               fields: fields)
        default: break
        }

        switch status {
        case 400, 422:
            return .validation(message: message.isEmpty ? "Please check the highlighted fields." : message,
                               fields: fields)
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 409: return .conflict(message.isEmpty ? "That record was changed elsewhere." : message)
        case 429: return .rateLimited(retryAfter: nil)
        default:
            return .server(status: status, message: message)
        }
    }
}
