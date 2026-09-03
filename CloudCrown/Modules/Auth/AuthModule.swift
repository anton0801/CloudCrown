//
//  AuthModule.swift
//  CloudCrown
//

import SwiftUI

// MARK: - Contract

@MainActor
protocol AuthInteractorInput: AnyObject {
    func register(email: String, password: String) async throws
    func signIn(email: String, password: String) async throws
    func syncAfterSignIn() async
    var localRecordCount: Int { get }
}

// MARK: - Router

@MainActor
final class AuthRouter: ObservableObject {
    @Published var didFinish = false
}

// MARK: - Builder

enum AuthModule {
    @MainActor
    static func build(environment: AppEnvironment, mode: AuthPresenter.Mode = .signIn) -> some View {
        let interactor = AuthInteractor(auth: environment.auth,
                                        sync: environment.sync,
                                        repository: environment.repository)
        let router = AuthRouter()
        let presenter = AuthPresenter(interactor: interactor, router: router, mode: mode)
        return AuthView(presenter: presenter, router: router)
    }
}
