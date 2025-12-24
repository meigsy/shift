//
//  ChatService.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import Foundation

class ChatService {
    private let baseURL: String
    private let authViewModel: AuthViewModel
    
    init(baseURL: String, authViewModel: AuthViewModel) {
        self.baseURL = baseURL
        self.authViewModel = authViewModel
    }
    
    func sendMessage(_ message: String, threadId: String) async throws -> AsyncThrowingStream<String, Error> {
        let token = try await authViewModel.getBearerToken()
        
        guard let url = URL(string: "\(baseURL)/chat") else {
            throw ChatError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "message": message,
            "thread_id": threadId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ChatError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                var currentLine = ""
                for try await byte in bytes {
                    if byte == 10 {  // Newline character
                        let line = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        currentLine = ""
                        
                        if line.hasPrefix("data: ") {
                            let content = String(line.dropFirst(6))
                            
                            if content.isEmpty {
                                continue
                            }
                            
                            if content == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            continuation.yield(content)
                        }
                    } else {
                        currentLine.append(Character(UnicodeScalar(byte)))
                    }
                }
                
                if !currentLine.isEmpty {
                    let line = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix("data: ") {
                        let content = String(line.dropFirst(6))
                        if !content.isEmpty && content != "[DONE]" {
                            continuation.yield(content)
                        }
                    }
                }
                
                continuation.finish()
            }
        }
    }
}

enum ChatError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        }
    }
}

