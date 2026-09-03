//
//  AuthModels.swift
//  CloudCrown
//

import Foundation

struct AuthUser: Codable, Equatable, Identifiable {
    let id: String
    let email: String
    let createdAt: Date
    var emailVerified: Bool
}

struct TokenPair: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry, computed on receipt from the server's `expiresIn`.
    var accessExpiresAt: Date

    /// Treated as expired slightly early so a request never races the clock.
    func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= accessExpiresAt
    }
}

/// Wire shape returned by /auth/register, /auth/login and /auth/refresh.
struct AuthSessionResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: AuthUser?

    func tokenPair(now: Date = Date()) -> TokenPair {
        TokenPair(accessToken: accessToken,
                  refreshToken: refreshToken,
                  accessExpiresAt: now.addingTimeInterval(TimeInterval(expiresIn)))
    }
}

struct AccountDeletionReceipt: Decodable, Equatable {
    let deletedAt: Date
    /// When the server purges the data for good.
    let purgeAt: Date?
    let message: String?
}

enum AuthState: Equatable {
    case signedOut
    case signedIn(AuthUser)

    var user: AuthUser? { if case .signedIn(let u) = self { return u }; return nil }
    var isSignedIn: Bool { user != nil }
}

// MARK: - Input validation

enum CredentialValidator {

    static func emailError(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Enter your email address." }
        // Deliberately permissive: the server is the authority on deliverability.
        let pattern = #"^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            return "That does not look like an email address."
        }
        return nil
    }

    static let minimumPasswordLength = 8

    static func passwordError(_ password: String) -> String? {
        if password.isEmpty { return "Enter a password." }
        if password.count < minimumPasswordLength {
            return "Use at least \(minimumPasswordLength) characters."
        }
        if password.rangeOfCharacter(from: .decimalDigits) == nil {
            return "Include at least one number."
        }
        if password.rangeOfCharacter(from: .letters) == nil {
            return "Include at least one letter."
        }
        return nil
    }

    static func confirmationError(_ password: String, _ confirmation: String) -> String? {
        confirmation.isEmpty ? "Repeat the password." : (password == confirmation ? nil : "The passwords do not match.")
    }
}
