//
//  ToolEventService.swift
//  ios_app
//
//  Created by SHIFT on 12/31/25.
//

import Foundation

@MainActor
class ToolEventService {
    private let apiClient: ApiClient
    private let chatViewModel: ChatViewModel?
    
    init(apiClient: ApiClient, chatViewModel: ChatViewModel? = nil) {
        self.apiClient = apiClient
        self.chatViewModel = chatViewModel
    }
    
    /// Send a tool event to the conversational agent
    /// - Parameters:
    ///   - type: Event type (e.g., "app_opened", "card_tapped", "flow_completed")
    ///   - interventionKey: Optional intervention key for card_tapped events
    ///   - suggestedAction: Optional suggested action text for card_tapped events
    ///   - context: Optional context string describing the event
    ///   - value: Optional value (for ratings, metrics, etc.)
    ///   - threadId: Optional thread ID (nil uses default active thread)
    /// - Returns: Agent's text response (if any)
    func sendToolEvent(
        type: String,
        interventionKey: String? = nil,
        suggestedAction: String? = nil,
        context: String? = nil,
        value: Any? = nil,
        threadId: String? = nil
    ) async throws -> String? {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        var eventPayload: [String: Any] = [
            "type": type,
            "timestamp": timestamp
        ]
        
        // Add optional fields if present
        if let key = interventionKey { eventPayload["intervention_key"] = key }
        if let action = suggestedAction { eventPayload["suggested_action"] = action }
        if let ctx = context { eventPayload["context"] = ctx }
        if let val = value { eventPayload["value"] = val }
        if let tid = threadId { eventPayload["thread_id"] = tid }
        
        print("📤 Sending tool event: type=\(type), intervention_key=\(interventionKey ?? "nil")")
        
        do {
            let response = try await apiClient.sendToolEvent(event: eventPayload)
            
            // Check response status
            guard let status = response["status"] as? String else {
                throw ToolEventError.invalidResponse
            }
            
            if status == "error" {
                let errorMsg = response["error"] as? String ?? "Unknown error"
                throw ToolEventError.serverError(message: errorMsg)
            }
            
            // Extract agent response text
            let agentResponse = response["response"] as? String
            
            // If agent responded with text, insert into chat (if chatViewModel available)
            if let text = agentResponse, !text.isEmpty, let chatVM = chatViewModel {
                chatVM.injectMessage(role: "assistant", text: text)
                print("💬 Agent response injected into chat: \(text.prefix(50))...")
            }
            
            print("✅ Tool event sent successfully (status: \(status))")
            return agentResponse
            
        } catch let error as ToolEventError {
            print("❌ Failed to send tool event: \(error.localizedDescription)")
            throw error
        } catch {
            print("❌ Failed to send tool event: \(error.localizedDescription)")
            throw ToolEventError.networkError(underlying: error)
        }
    }
}

// MARK: - Errors

enum ToolEventError: LocalizedError {
    case invalidResponse
    case serverError(message: String)
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

