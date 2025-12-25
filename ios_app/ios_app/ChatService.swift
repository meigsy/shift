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
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
            "location": "ChatService.swift:19",
            "message": "sendMessage called",
            "data": ["baseURL": baseURL, "messageLength": message.count, "threadId": threadId],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((logString + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
        
        let token = try await authViewModel.getBearerToken()
        let fullURL = "\(baseURL)/chat"
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "location": "ChatService.swift:26",
            "message": "URL constructed",
            "data": ["fullURL": fullURL, "baseURL": baseURL],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((logString + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
        
        guard let url = URL(string: fullURL) else {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "B",
                "location": "ChatService.swift:30",
                "message": "Invalid URL",
                "data": ["fullURL": fullURL],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                }
            }
            // #endregion
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
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "C",
            "location": "ChatService.swift:48",
            "message": "Request prepared",
            "data": ["url": url.absoluteString, "method": "POST", "hasToken": !token.isEmpty, "bodyKeys": Array(requestBody.keys)],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((logString + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
        
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "C",
                "location": "ChatService.swift:54",
                "message": "Invalid response type",
                "data": ["responseType": String(describing: type(of: response))],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                }
            }
            // #endregion
            throw ChatError.invalidResponse
        }
        
        // #region agent log
        if let logData = try? JSONSerialization.data(withJSONObject: [
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "A",
            "location": "ChatService.swift:60",
            "message": "HTTP response received",
            "data": ["statusCode": httpResponse.statusCode, "url": httpResponse.url?.absoluteString ?? "nil"],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
        ]), let logString = String(data: logData, encoding: .utf8) {
            let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((logString + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
            }
        }
        // #endregion
        
        guard (200...299).contains(httpResponse.statusCode) else {
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "A",
                "location": "ChatService.swift:66",
                "message": "HTTP error status",
                "data": ["statusCode": httpResponse.statusCode, "url": httpResponse.url?.absoluteString ?? "nil"],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
            ]), let logString = String(data: logData, encoding: .utf8) {
                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                    fileHandle.closeFile()
                } else {
                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                }
            }
            // #endregion
            
            if httpResponse.statusCode == 404 {
                if baseURL.contains("xxx") || baseURL.contains("placeholder") {
                    throw ChatError.serviceNotConfigured
                }
            }
            throw ChatError.httpError(statusCode: httpResponse.statusCode)
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                var currentLine = ""
                var lineCount = 0
                var chunkCount = 0
                
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "E",
                    "location": "ChatService.swift:199",
                    "message": "Starting SSE stream parsing",
                    "data": [:],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                ]), let logString = String(data: logData, encoding: .utf8) {
                    let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write((logString + "\n").data(using: .utf8)!)
                        fileHandle.closeFile()
                    } else {
                        try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                    }
                }
                // #endregion
                
                do {
                    var rawBytes: [UInt8] = []
                    var byteCount = 0
                    
                    for try await byte in bytes {
                        byteCount += 1
                        rawBytes.append(byte)
                        
                        // Log first 200 bytes for debugging
                        if byteCount <= 200 {
                            // #region agent log
                            if let logData = try? JSONSerialization.data(withJSONObject: [
                                "sessionId": "debug-session",
                                "runId": "run1",
                                "hypothesisId": "G",
                                "location": "ChatService.swift:227",
                                "message": "Raw byte received",
                                "data": ["byteNumber": byteCount, "byteValue": byte, "isNewline": byte == 10, "currentLineLength": currentLine.count],
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]), let logString = String(data: logData, encoding: .utf8) {
                                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                    fileHandle.seekToEndOfFile()
                                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                                    fileHandle.closeFile()
                                } else {
                                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                                }
                            }
                            // #endregion
                        }
                        
                        if byte == 10 {  // Newline character
                            lineCount += 1
                            let line = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // #region agent log
                            if let logData = try? JSONSerialization.data(withJSONObject: [
                                "sessionId": "debug-session",
                                "runId": "run1",
                                "hypothesisId": "E",
                                "location": "ChatService.swift:250",
                                "message": "Line received",
                                "data": ["lineNumber": lineCount, "line": line, "lineLength": line.count, "hasDataPrefix": line.hasPrefix("data: "), "firstChars": String(line.prefix(20))],
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]), let logString = String(data: logData, encoding: .utf8) {
                                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                    fileHandle.seekToEndOfFile()
                                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                                    fileHandle.closeFile()
                                } else {
                                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                                }
                            }
                            // #endregion
                            
                            currentLine = ""
                            
                            // Handle both SSE format (data: <content>) and plain text
                            var content: String = ""
                            if line.hasPrefix("data: ") {
                                content = String(line.dropFirst(6))
                            } else if !line.isEmpty {
                                // Plain text line - treat as content
                                content = line
                            }
                            
                            if content.isEmpty {
                                continue
                            }
                            
                            if content == "[DONE]" {
                                // #region agent log
                                if let logData = try? JSONSerialization.data(withJSONObject: [
                                    "sessionId": "debug-session",
                                    "runId": "run1",
                                    "hypothesisId": "E",
                                    "location": "ChatService.swift:273",
                                    "message": "Received [DONE] marker",
                                    "data": ["chunkCount": chunkCount],
                                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                                ]), let logString = String(data: logData, encoding: .utf8) {
                                    let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                                    if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                        fileHandle.seekToEndOfFile()
                                        fileHandle.write((logString + "\n").data(using: .utf8)!)
                                        fileHandle.closeFile()
                                    } else {
                                        try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                                    }
                                }
                                // #endregion
                                continuation.finish()
                                return
                            }
                            
                            chunkCount += 1
                            // #region agent log
                            if let logData = try? JSONSerialization.data(withJSONObject: [
                                "sessionId": "debug-session",
                                "runId": "run1",
                                "hypothesisId": "E",
                                "location": "ChatService.swift:300",
                                "message": "Yielding chunk",
                                "data": ["chunkNumber": chunkCount, "content": content, "contentLength": content.count, "wasSSEFormat": line.hasPrefix("data: ")],
                                "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                            ]), let logString = String(data: logData, encoding: .utf8) {
                                let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                    fileHandle.seekToEndOfFile()
                                    fileHandle.write((logString + "\n").data(using: .utf8)!)
                                    fileHandle.closeFile()
                                } else {
                                    try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                                }
                            }
                            // #endregion
                            
                            continuation.yield(content)
                        } else {
                            currentLine.append(Character(UnicodeScalar(byte)))
                        }
                    }
                    
                    // Log raw bytes preview at end
                    if !rawBytes.isEmpty {
                        let preview = String(data: Data(rawBytes.prefix(200)), encoding: .utf8) ?? "invalid utf8"
                        // #region agent log
                        if let logData = try? JSONSerialization.data(withJSONObject: [
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "G",
                            "location": "ChatService.swift:330",
                            "message": "Raw bytes preview",
                            "data": ["totalBytes": rawBytes.count, "preview": preview, "firstBytesHex": rawBytes.prefix(50).map { String(format: "%02x", $0) }.joined(separator: " ")],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                        ]), let logString = String(data: logData, encoding: .utf8) {
                            let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                                fileHandle.seekToEndOfFile()
                                fileHandle.write((logString + "\n").data(using: .utf8)!)
                                fileHandle.closeFile()
                            } else {
                                try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                            }
                        }
                        // #endregion
                    }
                    
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "E",
                        "location": "ChatService.swift:280",
                        "message": "Stream ended (bytes exhausted)",
                        "data": ["lineCount": lineCount, "chunkCount": chunkCount, "remainingLine": currentLine],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write((logString + "\n").data(using: .utf8)!)
                            fileHandle.closeFile()
                        } else {
                            try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                        }
                    }
                    // #endregion
                    
                    if !currentLine.isEmpty {
                        let line = currentLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        var content: String = ""
                        if line.hasPrefix("data: ") {
                            content = String(line.dropFirst(6))
                        } else if !line.isEmpty {
                            content = line
                        }
                        if !content.isEmpty && content != "[DONE]" {
                            continuation.yield(content)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    // #region agent log
                    if let logData = try? JSONSerialization.data(withJSONObject: [
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "E",
                        "location": "ChatService.swift:300",
                        "message": "Stream error",
                        "data": ["error": error.localizedDescription, "lineCount": lineCount, "chunkCount": chunkCount],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
                    ]), let logString = String(data: logData, encoding: .utf8) {
                        let logPath = "/Users/sly/dev/shift/.cursor/debug.log"
                        if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                            fileHandle.seekToEndOfFile()
                            fileHandle.write((logString + "\n").data(using: .utf8)!)
                            fileHandle.closeFile()
                        } else {
                            try? (logString + "\n").write(toFile: logPath, atomically: true, encoding: .utf8)
                        }
                    }
                    // #endregion
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

