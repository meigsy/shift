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
        
        // #region agent log
        let logData: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "initial",
            "hypothesisId": "C",
            "location": "ApiClient.swift:28",
            "message": "Starting URLSession request",
            "data": [
                "url": url.absoluteString,
                "hasToken": idToken != nil
            ],
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            if let logFile = FileHandle(forWritingAtPath: "/Users/sly/dev/shift/.cursor/debug.log") {
                try? logFile.seekToEnd()
                logFile.write((jsonString + "\n").data(using: .utf8)!)
                try? logFile.close()
            } else {
                try? (jsonString + "\n").write(toFile: "/Users/sly/dev/shift/.cursor/debug.log", atomically: false, encoding: .utf8)
            }
        }
        // #endregion
        
        // Perform request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                // #region agent log
                let logData2: [String: Any] = [
                    "sessionId": "debug-session",
                    "runId": "initial",
                    "hypothesisId": "C",
                    "location": "ApiClient.swift:46",
                    "message": "Invalid response type (not HTTPURLResponse)",
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: logData2),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    if let logFile = FileHandle(forWritingAtPath: "/Users/sly/dev/shift/.cursor/debug.log") {
                        try? logFile.seekToEnd()
                        logFile.write((jsonString + "\n").data(using: .utf8)!)
                        try? logFile.close()
                    } else {
                        try? (jsonString + "\n").write(toFile: "/Users/sly/dev/shift/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                }
                // #endregion
                throw ApiError.httpError(statusCode: 0, message: "Invalid response type")
            }
            
            // #region agent log
            let logData3: [String: Any] = [
                "sessionId": "debug-session",
                "runId": "initial",
                "hypothesisId": "C",
                "location": "ApiClient.swift:51",
                "message": "Received HTTP response",
                "data": [
                    "statusCode": httpResponse.statusCode,
                    "dataLength": data.count
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: logData3),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if let logFile = FileHandle(forWritingAtPath: "/Users/sly/dev/shift/.cursor/debug.log") {
                    try? logFile.seekToEnd()
                    logFile.write((jsonString + "\n").data(using: .utf8)!)
                    try? logFile.close()
                } else {
                    try? (jsonString + "\n").write(toFile: "/Users/sly/dev/shift/.cursor/debug.log", atomically: false, encoding: .utf8)
                }
            }
            // #endregion
            
            // Handle HTTP status codes
            if httpResponse.statusCode == 401 {
                throw ApiError.unauthorized
            }
            
            if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                // #region agent log
                let logData4: [String: Any] = [
                    "sessionId": "debug-session",
                    "runId": "initial",
                    "hypothesisId": "C",
                    "location": "ApiClient.swift:55",
                    "message": "HTTP error status code",
                    "data": [
                        "statusCode": httpResponse.statusCode,
                        "message": message
                    ],
                    "timestamp": Int(Date().timeIntervalSince1970 * 1000)
                ]
                if let jsonData = try? JSONSerialization.data(withJSONObject: logData4),
                   let jsonString = String(data: jsonData, encoding: .utf8) {
                    if let logFile = FileHandle(forWritingAtPath: "/Users/sly/dev/shift/.cursor/debug.log") {
                        try? logFile.seekToEnd()
                        logFile.write((jsonString + "\n").data(using: .utf8)!)
                        try? logFile.close()
                    } else {
                        try? (jsonString + "\n").write(toFile: "/Users/sly/dev/shift/.cursor/debug.log", atomically: false, encoding: .utf8)
                    }
                }
                // #endregion
                throw ApiError.httpError(statusCode: httpResponse.statusCode, message: message)
            }
            
            return data
        } catch let error as ApiError {
            throw error
        } catch {
            // #region agent log
            let logData5: [String: Any] = [
                "sessionId": "debug-session",
                "runId": "initial",
                "hypothesisId": "C",
                "location": "ApiClient.swift:64",
                "message": "Network/URLSession error",
                "data": [
                    "error": error.localizedDescription,
                    "errorType": String(describing: type(of: error))
                ],
                "timestamp": Int(Date().timeIntervalSince1970 * 1000)
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: logData5),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                if let logFile = FileHandle(forWritingAtPath: "/Users/sly/dev/shift/.cursor/debug.log") {
                    try? logFile.seekToEnd()
                    logFile.write((jsonString + "\n").data(using: .utf8)!)
                    try? logFile.close()
                } else {
                    try? (jsonString + "\n").write(toFile: "/Users/sly/dev/shift/.cursor/debug.log", atomically: false, encoding: .utf8)
                }
            }
            // #endregion
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
}
