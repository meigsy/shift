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
}

class ApiClient {
    private let baseURL: String
    private var idToken: String?
    
    init(baseURL: String, idToken: String?) {
        self.baseURL = baseURL
        self.idToken = idToken
    }
    
    func setToken(_ token: String?) {
        self.idToken = token
    }
    
    func get(path: String) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw ApiError.httpError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Bearer token if available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ApiError.httpError(statusCode: 0, message: "Invalid response type")
            }
            
            // Handle HTTP status codes
            if httpResponse.statusCode == 401 {
                throw ApiError.unauthorized
            }
            
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.httpError(statusCode: 0, message: error.localizedDescription)
        }
    }
    
    func post(path: String, body: Encodable) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw ApiError.httpError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Bearer token if available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode body to JSON
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
        } catch {
            throw ApiError.httpError(statusCode: 0, message: "Failed to encode request body: \(error.localizedDescription)")
        }
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ApiError.httpError(statusCode: 0, message: "Invalid response type")
            }
            
            // Handle HTTP status codes
            if httpResponse.statusCode == 401 {
                throw ApiError.unauthorized
            }
            
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            throw ApiError.httpError(statusCode: 0, message: error.localizedDescription)
        }
    }
    
    func post(path: String, bodyData: Data) async throws -> Data {
        // #region agent log
        let fullURL = baseURL + path
        let logData1: [String: Any] = [
            "location": "ApiClient.swift:117",
            "message": "post(bodyData) entry",
            "data": ["baseURL": baseURL, "path": path, "fullURL": fullURL, "hasToken": idToken != nil],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B"
        ]
        if let logJson = try? JSONSerialization.data(withJSONObject: logData1),
           let logStr = String(data: logJson, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        guard let url = URL(string: baseURL + path) else {
            // #region agent log
            let logData: [String: Any] = [
                "location": "ApiClient.swift:133",
                "message": "Invalid URL",
                "data": ["baseURL": baseURL, "path": path, "attemptedURL": baseURL + path],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "B"
            ]
            if let logJson = try? JSONSerialization.data(withJSONObject: logData),
               let logStr = String(data: logJson, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            throw ApiError.httpError(statusCode: 0, message: "Invalid URL: \(baseURL + path)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Bearer token if available
        if let token = idToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = bodyData
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // #region agent log
            let logData2: [String: Any] = [
                "location": "ApiClient.swift:160",
                "message": "HTTP response received",
                "data": [
                    "statusCode": (response as? HTTPURLResponse)?.statusCode ?? 0,
                    "responseDataLength": data.count
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "D"
            ]
            if let logJson = try? JSONSerialization.data(withJSONObject: logData2),
               let logStr = String(data: logJson, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ApiError.httpError(statusCode: 0, message: "Invalid response type")
            }
            
            // Handle HTTP status codes
            if httpResponse.statusCode == 401 {
                // #region agent log
                let logData: [String: Any] = [
                    "location": "ApiClient.swift:177",
                    "message": "Unauthorized (401)",
                    "data": ["statusCode": 401],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "A"
                ]
                if let logJson = try? JSONSerialization.data(withJSONObject: logData),
                   let logStr = String(data: logJson, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                throw ApiError.unauthorized
            }
            
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                // #region agent log
                let logData: [String: Any] = [
                    "location": "ApiClient.swift:193",
                    "message": "HTTP error status",
                    "data": ["statusCode": httpResponse.statusCode, "message": message],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "D"
                ]
                if let logJson = try? JSONSerialization.data(withJSONObject: logData),
                   let logStr = String(data: logJson, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            // #region agent log
            let logData: [String: Any] = [
                "location": "ApiClient.swift:210",
                "message": "Network error caught",
                "data": [
                    "errorType": String(describing: type(of: error)),
                    "errorDescription": String(describing: error),
                    "localizedDescription": error.localizedDescription
                ],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "C"
            ]
            if let logJson = try? JSONSerialization.data(withJSONObject: logData),
               let logStr = String(data: logJson, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            throw ApiError.httpError(statusCode: 0, message: error.localizedDescription)
        }
    }
}

extension String {
    func appendLineToFile(filePath: String) throws {
        let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        if let data = (self + "\n").data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
        }
    }
}
