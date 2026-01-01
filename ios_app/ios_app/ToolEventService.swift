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
    
    /// Get the active thread ID from ChatViewModel, or construct default if not available
    private func getThreadId(override: String? = nil) -> String {
        // If explicit override provided, use it
        if let override = override {
            return override
        }
        
        // Use ChatViewModel's active thread if available
        if let chatVM = chatViewModel {
            return chatVM.activeThreadId
        }
        
        // Fallback: just return "active" and let backend construct full thread ID
        return "active"
    }
    
    /// Send a tool event to the conversational agent
    /// - Parameters:
    ///   - type: Event type (e.g., "app_opened", "card_tapped", "flow_completed")
    ///   - interventionKey: Optional intervention key for card_tapped events
    ///   - suggestedAction: Optional suggested action text for card_tapped events
    ///   - context: Optional context string describing the event
    ///   - value: Optional value (for ratings, metrics, etc.)
    ///   - threadId: Optional thread ID (nil uses default active thread)
    /// - Returns: Tuple of (response text, optional AgentCard)
    func sendToolEvent(
        type: String,
        interventionKey: String? = nil,
        suggestedAction: String? = nil,
        context: String? = nil,
        value: Any? = nil,
        threadId: String? = nil
    ) async throws -> (response: String?, card: AgentCard?) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        
        // Get the correct thread ID - use ChatViewModel's active thread to ensure consistency
        let effectiveThreadId = getThreadId(override: threadId)
        
        var eventPayload: [String: Any] = [
            "type": type,
            "timestamp": timestamp,
            "thread_id": effectiveThreadId  // ALWAYS include thread_id for consistency
        ]
        
        // Add optional fields if present
        if let key = interventionKey { eventPayload["intervention_key"] = key }
        if let action = suggestedAction { eventPayload["suggested_action"] = action }
        if let ctx = context { eventPayload["context"] = ctx }
        if let val = value { eventPayload["value"] = val }
        
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
            
            // Parse card if present
            var card: AgentCard? = nil
            if let cardData = response["card"] as? [String: Any] {
                do {
                    let cardJson = try JSONSerialization.data(withJSONObject: cardData)
                    card = try JSONDecoder().decode(AgentCard.self, from: cardJson)
                    print("📇 Card parsed: \(card?.title ?? "unknown")")
                } catch {
                    print("⚠️ Failed to parse card: \(error)")
                }
            }
            
            // DO NOT auto-inject here - let the caller decide when/how to inject
            // This prevents double-injection when caller also injects
            
            print("✅ Tool event sent successfully (status: \(status))")
            return (agentResponse, card)
            
            print("✅ Tool event sent successfully (status: \(status))")
            return (agentResponse, card)
            
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

