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
        let fullURL = "\(baseURL)/chat"
        
        guard let url = URL(string: fullURL) else {
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
            if httpResponse.statusCode == 404 {
                if baseURL.contains("xxx") || baseURL.contains("placeholder") {
                    throw ChatError.serviceNotConfigured
                }
            }
            throw ChatError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var lineBuffer: [UInt8] = []
                    
                    for try await byte in bytes {
                        if byte == 10 {  // Newline character
                            // Decode UTF-8 properly from byte buffer
                            let line = String(data: Data(lineBuffer), encoding: .utf8) ?? ""
                            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            lineBuffer = []
                            
                            // Handle both SSE format (data: <content>) and plain text
                            var content: String = ""
                            if trimmedLine.hasPrefix("data: ") {
                                content = String(trimmedLine.dropFirst(6))
                            } else if !trimmedLine.isEmpty {
                                // Plain text line - treat as content
                                content = trimmedLine
                            }
                            
                            if content.isEmpty {
                                continue
                            }
                            
                            if content == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            continuation.yield(content)
                        } else {
                            // Collect bytes for proper UTF-8 decoding
                            lineBuffer.append(byte)
                        }
                    }
                    
                    // Handle any remaining bytes in buffer
                    if !lineBuffer.isEmpty {
                        if let line = String(data: Data(lineBuffer), encoding: .utf8) {
                            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            var content: String = ""
                            if trimmedLine.hasPrefix("data: ") {
                                content = String(trimmedLine.dropFirst(6))
                            } else if !trimmedLine.isEmpty {
                                content = trimmedLine
                            }
                            if !content.isEmpty && content != "[DONE]" {
                                continuation.yield(content)
                            }
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

enum ChatError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case serviceNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .serviceNotConfigured:
            return "Chat service not configured. Please set CONVERSATIONAL_AGENT_BASE_URL in Info.plist with the deployed service URL."
        }
    }
}

