//
//  AppSupport.swift
//  CloudCrown
//

import Foundation

/// Contact details shown in the app. This mailbox must be monitored: it is the
/// only route to account deletion for someone who has lost their password, and
/// App Review checks that a published support contact works.
enum AppSupport {
    static let email = "support@cloudcrown-app.space"
    static let website = "https://cloudcrown-app.space"
    static let privacyPolicy = "https://cloudcrown-app.space/privacy"
}
