//
//  APIConfiguration.swift
//  CloudCrown
//
//  Base configuration for the CloudCrown REST API.
//

import Foundation

struct APIConfiguration {

    let baseURL: URL
    /// Requests fail rather than hang forever.
    let timeout: TimeInterval

    static let production = APIConfiguration(
        baseURL: URL(string: "https://cloudcrown-app.space/api/v1")!,
        timeout: 20
    )

    static var current: APIConfiguration {
        return .production
    }
}
