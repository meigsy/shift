//
//  ApiClient.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation

@MainActor
class ApiClient {
    
    private let baseURL: String
    private var idToken: String?
    
    init(baseURL: String, idToken: String? = nil) {
        self.baseURL = baseURL
        self.idToken = idToken
    }
    
    func setToken(_ token: String?) {
        self.idToken = token
    }
    
    // MARK: - Authenticated Request
    
    func authenticatedRequest(
        path: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw ApiError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authentication header if token is available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ApiError.invalidResponse
        }
        
        // Handle 401 Unauthorized (token expired)
        if httpResponse.statusCode == 401 {
            throw ApiError.unauthorized
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ApiError.httpError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        return (data, httpResponse)
    }
    
    // MARK: - POST Request
    
    func post<T: Encodable>(path: String, body: T) async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let bodyData = try encoder.encode(body)
        let (data, _) = try await authenticatedRequest(path: path, method: "POST", body: bodyData)
        return data
    }
    
    // MARK: - GET Request
    
    func get(path: String) async throws -> Data {
        let (data, _) = try await authenticatedRequest(path: path, method: "GET")
        return data
    }
}

// MARK: - Errors

enum ApiError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, message: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - token expired or invalid"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        }
    }
}







