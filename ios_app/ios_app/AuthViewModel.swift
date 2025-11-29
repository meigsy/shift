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
        print("🔵 AuthViewModel: signInWithApple() called")
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        print("🔵 AuthViewModel: Performing Sign in with Apple request...")
        authorizationController.performRequests()
    }
    
    // MARK: - Test Bypass (for simulator testing)
    
    func signInWithMock() {
        print("🧪 AuthViewModel: Using mock sign-in bypass for testing")
        // Simulate Apple Sign In with mock tokens
        let mockIdentityToken = "mock.apple.identity.token.\(UUID().uuidString)"
        let mockAuthorizationCode = "mock.apple.auth.code.\(UUID().uuidString)"
        
        Task {
            do {
                try await authenticateWithBackend(
                    identityToken: mockIdentityToken,
                    authorizationCode: mockAuthorizationCode
                )
                print("✅ AuthViewModel: Mock authentication successful!")
            } catch {
                print("❌ AuthViewModel: Mock authentication failed: \(error.localizedDescription)")
                errorMessage = "Mock authentication failed: \(error.localizedDescription)"
            }
        }
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
        let fullURL = "\(backendBaseURL)\(authPath)"
        print("🟡 AuthViewModel: Authenticating with backend: \(fullURL)")
        guard let url = URL(string: fullURL) else {
            print("❌ AuthViewModel: Invalid URL: \(fullURL)")
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
        
        print("🟡 AuthViewModel: Sending request to backend...")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ AuthViewModel: Invalid response type")
            throw AuthError.invalidResponse
        }
        
        print("🟡 AuthViewModel: Backend response status: \(httpResponse.statusCode)")
        print("🟡 AuthViewModel: Response data length: \(data.count) bytes")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ AuthViewModel: Backend error: \(httpResponse.statusCode) - \(errorBody)")
            throw AuthError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("🟡 AuthViewModel: Raw response: \(responseString)")
        }
        
        // Parse response
        let decoder = JSONDecoder()
        
        // Custom date formatter to handle backend dates without timezone (assumes UTC)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0) // Assume UTC
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        do {
            let authResponse = try decoder.decode(AuthResponse.self, from: data)
            print("🟢 AuthViewModel: Backend response parsed successfully")
            print("🟢 AuthViewModel: User ID: \(authResponse.user.userId)")
            
            // Save token
            saveToken(authResponse.idToken)
            print("🟢 AuthViewModel: Token saved")
            
            // Set user
            user = authResponse.user
            isAuthenticated = true
            print("🟢 AuthViewModel: Authentication state updated - isAuthenticated: \(isAuthenticated)")
        } catch {
            print("❌ AuthViewModel: JSON decode error: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("❌ AuthViewModel: Data corrupted: \(context)")
                case .keyNotFound(let key, let context):
                    print("❌ AuthViewModel: Key not found: \(key.stringValue) - \(context)")
                case .typeMismatch(let type, let context):
                    print("❌ AuthViewModel: Type mismatch: \(type) - \(context)")
                case .valueNotFound(let type, let context):
                    print("❌ AuthViewModel: Value not found: \(type) - \(context)")
                @unknown default:
                    print("❌ AuthViewModel: Unknown decoding error")
                }
            }
            throw error
        }
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
        print("🟢 AuthViewModel: didCompleteWithAuthorization called")
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            print("🟢 AuthViewModel: Got Apple ID credential")
            guard let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                print("❌ AuthViewModel: Failed to get identity token")
                errorMessage = "Failed to get identity token"
                return
            }
            print("🟢 AuthViewModel: Got identity token (length: \(identityToken.count))")
            
            guard let authorizationCodeData = appleIDCredential.authorizationCode,
                  let authorizationCode = String(data: authorizationCodeData, encoding: .utf8) else {
                print("❌ AuthViewModel: Failed to get authorization code")
                errorMessage = "Failed to get authorization code"
                return
            }
            print("🟢 AuthViewModel: Got authorization code (length: \(authorizationCode.count))")
            
            // Authenticate with backend
            print("🟢 AuthViewModel: Calling authenticateWithBackend...")
            Task {
                do {
                    try await authenticateWithBackend(
                        identityToken: identityToken,
                        authorizationCode: authorizationCode
                    )
                    print("✅ AuthViewModel: Authentication successful!")
                } catch {
                    print("❌ AuthViewModel: Authentication failed: \(error.localizedDescription)")
                    errorMessage = "Authentication failed: \(error.localizedDescription)"
                }
            }
        } else {
            print("❌ AuthViewModel: Credential is not ASAuthorizationAppleIDCredential")
        }
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("❌ AuthViewModel: didCompleteWithError called: \(error.localizedDescription)")
        if let authError = error as? ASAuthorizationError {
            print("❌ AuthViewModel: ASAuthorizationError code: \(authError.code.rawValue)")
        }
        errorMessage = "Sign in with Apple failed: \(error.localizedDescription)"
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthViewModel: ASAuthorizationControllerPresentationContextProviding {
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        print("🟡 AuthViewModel: presentationAnchor called")
        // Get the window from the scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            print("❌ AuthViewModel: No window available for presentation")
            fatalError("No window available")
        }
        print("🟢 AuthViewModel: Returning window for presentation")
        return window
    }
}

// MARK: - Models

struct AuthResponse: Codable {
    let idToken: String
    let refreshToken: String?
    let expiresIn: Int
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
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

