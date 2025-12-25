//
//  ChatViewModel.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import Foundation
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let chatService: ChatService
    private let authViewModel: AuthViewModel
    private(set) var activeThreadId: String
    
    init(chatService: ChatService, authViewModel: AuthViewModel) {
        self.chatService = chatService
        self.authViewModel = authViewModel
        
        let userId = authViewModel.user?.userId ?? "debug-user"
        self.activeThreadId = "user_\(userId)_active"
    }
    
    func sendMessage(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = ChatMessage(role: "user", text: text)
        messages.append(userMessage)
        
        isLoading = true
        errorMessage = nil
        
        var assistantMessage = ChatMessage(role: "assistant", text: "")
        let assistantIndex = messages.count
        messages.append(assistantMessage)
        
        do {
            let stream = try await chatService.sendMessage(text, threadId: activeThreadId)
            
            var chunkCount = 0
            for try await chunk in stream {
                chunkCount += 1
                // #region agent log
                if let logData = try? JSONSerialization.data(withJSONObject: [
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "F",
                    "location": "ChatViewModel.swift:47",
                    "message": "Chunk received in ViewModel",
                    "data": ["chunkNumber": chunkCount, "chunkLength": chunk.count, "chunkPreview": String(chunk.prefix(50))],
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
                
                await MainActor.run {
                    assistantMessage = ChatMessage(
                        id: assistantMessage.id,
                        role: assistantMessage.role,
                        text: assistantMessage.text + chunk,
                        createdAt: assistantMessage.createdAt
                    )
                    messages[assistantIndex] = assistantMessage
                }
            }
            
            // #region agent log
            if let logData = try? JSONSerialization.data(withJSONObject: [
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "F",
                "location": "ChatViewModel.swift:70",
                "message": "Stream completed",
                "data": ["totalChunks": chunkCount, "finalMessageLength": assistantMessage.text.count],
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
            
            await MainActor.run {
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                if let chatError = error as? ChatError {
                    errorMessage = chatError.localizedDescription
                } else {
                    let nsError = error as NSError
                    if nsError.domain == NSURLErrorDomain {
                        switch nsError.code {
                        case NSURLErrorNotConnectedToInternet:
                            errorMessage = "No internet connection"
                        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                            errorMessage = "Cannot connect to chat service. Please check CONVERSATIONAL_AGENT_BASE_URL in Info.plist."
                        case NSURLErrorTimedOut:
                            errorMessage = "Request timed out"
                        default:
                            errorMessage = "Network error: \(nsError.localizedDescription)"
                        }
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
                if let index = messages.firstIndex(where: { $0.id == assistantMessage.id }) {
                    messages.remove(at: index)
                }
            }
        }
    }
    
    func startNewChat() {
        let userId = authViewModel.user?.userId ?? "debug-user"
        activeThreadId = "user_\(userId)_thread_\(UUID().uuidString)"
        messages.removeAll()
        errorMessage = nil
    }
}

