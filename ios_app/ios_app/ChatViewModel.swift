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
        
        let assistantMessageId = UUID()
        var accumulatedText = ""
        let assistantMessage = ChatMessage(id: assistantMessageId, role: "assistant", text: "")
        let assistantIndex = messages.count
        messages.append(assistantMessage)
        
        do {
            let stream = try await chatService.sendMessage(text, threadId: activeThreadId)
            
            for try await chunk in stream {
                await MainActor.run {
                    accumulatedText += chunk
                    let updatedMessage = ChatMessage(
                        id: assistantMessageId,
                        role: "assistant",
                        text: accumulatedText,
                        createdAt: assistantMessage.createdAt
                    )
                    messages[assistantIndex] = updatedMessage
                }
            }
            
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
                if let index = messages.firstIndex(where: { $0.id == assistantMessageId }) {
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
    
    // MARK: - Card and Message Injection
    
    /// Inject a message into the chat (non-streaming)
    func injectMessage(role: String = "assistant", text: String) {
        // #region agent log
        let logData: [String: Any] = [
            "location": "ChatViewModel.swift:103",
            "message": "injectMessage called",
            "data": [
                "role": role,
                "textPreview": text.prefix(100),
                "textLength": text.count,
                "currentMessageCount": messages.count,
                "activeThreadId": activeThreadId
            ],
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
        
        let message = ChatMessage(role: role, text: text)
        messages.append(message)
    }
    
    /// Insert a card into messages if it doesn't already exist (deduplication by card.id)
    func insertCard(_ card: ChatCard) {
        // Check if card with same id already exists
        let cardExists = messages.contains { message in
            if case .card(let existingCard) = message.kind {
                return existingCard.id == card.id
            }
            return false
        }
        
        if !cardExists {
            let cardMessage = ChatMessage(role: "system", card: card)
            messages.append(cardMessage)
        }
    }
    
    /// Remove a card message by card id
    func removeCard(cardId: String) {
        messages.removeAll { message in
            if case .card(let card) = message.kind {
                return card.id == cardId
            }
            return false
        }
    }
    
    // MARK: - Onboarding
    // Onboarding logic is now handled by backend selector via /context endpoint
    // Removed UserDefaults-based onboarding check - backend decides when to show getting_started
}
