//
//  ApiClient.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation

enum ApiError: Error {
    case unauthorized
    case httpError(statusCode: Int, message: String)
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
}

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
    
    func post<T: Encodable>(path: String, body: T) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw ApiError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization header if token is available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode body
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw ApiError.decodingError(error)
        }
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ApiError.invalidResponse
            }
            
            // Check status code
            if httpResponse.statusCode == 401 {
                throw ApiError.unauthorized
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.networkError(error)
        }
    }
    
    func get<T: Decodable>(path: String, queryItems: [URLQueryItem]? = nil) async throws -> T {
        var urlComponents = URLComponents(string: baseURL + path)
        if let queryItems = queryItems {
            urlComponents?.queryItems = queryItems
        }
        
        guard let url = urlComponents?.url else {
            throw ApiError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Add authorization header if token is available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ApiError.invalidResponse
            }
            
            // Check status code
            if httpResponse.statusCode == 401 {
                throw ApiError.unauthorized
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            // Decode response
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw ApiError.decodingError(error)
            }
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.networkError(error)
        }
    }
}
