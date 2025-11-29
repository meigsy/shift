//
//  AuthViewModel.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation
import AuthenticationServices
import Combine

@MainActor
class AuthViewModel: NSObject, ObservableObject {
    
    @Published var isAuthenticated = false
    @Published var idToken: String?
    @Published var user: User?
    @Published var errorMessage: String?
    
    let backendBaseURL: String
    let useMockAuth: Bool
    private let tokenKey = "com.shift.ios-app.idToken"
    private let userIdKey = "com.shift.ios-app.userId"
    
    init(backendBaseURL: String = "https://api.shift.example.com", useMockAuth: Bool = false) {
        self.backendBaseURL = backendBaseURL
        self.useMockAuth = useMockAuth
        super.init()
        
        // Check for existing token on init
        if let savedToken = UserDefaults.standard.string(forKey: tokenKey) {
            self.idToken = savedToken
            self.isAuthenticated = true
            // Try to fetch user info
            Task {
                await fetchUserInfo()
            }
        }
    }
    
    // MARK: - Sign in with Apple
    
    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
    }
    
    // MARK: - Sign Out
    
    func signOut() {
        idToken = nil
        user = nil
        isAuthenticated = false
        errorMessage = nil
        
        // Clear stored token
        UserDefaults.standard.removeObject(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
    }
    
    // MARK: - Token Management
    
    private func saveToken(_ token: String) {
        idToken = token
        UserDefaults.standard.set(token, forKey: tokenKey)
    }
    
    // MARK: - Backend API Calls
    
    private func authenticateWithBackend(identityToken: String, authorizationCode: String) async throws {
        // Use mock endpoint if enabled (for testing without Apple Developer account)
        let authPath = useMockAuth ? "/auth/apple/mock" : "/auth/apple"
        guard let url = URL(string: "\(backendBaseURL)\(authPath)") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "identity_token": identityToken,
            "authorization_code": authorizationCode
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Parse response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let authResponse = try decoder.decode(AuthResponse.self, from: data)
        
        // Save token
        saveToken(authResponse.idToken)
        
        // Set user
        user = authResponse.user
        isAuthenticated = true
    }
    
    func fetchUserInfo() async {
        guard let token = idToken else {
            errorMessage = "No authentication token"
            return
        }
        
        guard let url = URL(string: "\(backendBaseURL)/me") else {
            errorMessage = "Invalid URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response"
                return
            }
            
            if httpResponse.statusCode == 401 {
                // Token expired, sign out
                signOut()
                errorMessage = "Session expired. Please sign in again."
                return
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                errorMessage = "Failed to fetch user info: \(errorBody)"
                return
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            user = try decoder.decode(User.self, from: data)
            isAuthenticated = true
            errorMessage = nil
            
        } catch {
            errorMessage = "Failed to fetch user info: \(error.localizedDescription)"
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthViewModel: ASAuthorizationControllerDelegate {
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Failed to get identity token"
                return
            }
            
            guard let authorizationCodeData = appleIDCredential.authorizationCode,
                  let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
                errorMessage = "Failed to get authorization code"
                return
            }
            
            // Authenticate with backend
            Task {
                do {
                    try await authenticateWithBackend(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode
                    )
                } catch {
                    errorMessage = "Authentication failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        errorMessage = "Sign in with Apple failed: \(error.localizedDescription)"
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the window from the scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("No window available")
        }
        return window
    }
}

// MARK: - Models

struct AuthResponse: Codable {
    let idToken: String
    let refreshToken: String?
    let expiresIn: Int
    let user: User
}

struct User: Codable, Identifiable {
    let id: String
    let userId: String
    let email: String?
    let displayName: String?
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case email
        case displayName = "display_name"
        case createdAt = "created_at"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        id = userId
        email = try container.decodeIfPresent(String.self, forKey: .email)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}

