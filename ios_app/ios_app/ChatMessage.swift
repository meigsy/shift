//
//  ChatMessage.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import Foundation

enum MessageKind: Equatable {
    case text(String)
    case card(ChatCard)
    case textWithCard(String, AgentCard)  // NEW: text message with attached agent card
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: String  // "user" | "assistant" | "system"
    let kind: MessageKind
    let createdAt: Date
    
    // Backward-compatible initializer (text-only)
    init(id: UUID = UUID(), role: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.kind = .text(text)
        self.createdAt = createdAt
    }
    
    // Text with optional agent card initializer (NEW)
    init(id: UUID = UUID(), role: String, text: String, agentCard: AgentCard?, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        if let card = agentCard {
            self.kind = .textWithCard(text, card)
        } else {
            self.kind = .text(text)
        }
        self.createdAt = createdAt
    }
    
    // Card initializer (legacy ChatCard)
    init(id: UUID = UUID(), role: String, card: ChatCard, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.kind = .card(card)
        self.createdAt = createdAt
    }
    
    // Convenience accessor for text (when kind is .text or .textWithCard)
    var text: String {
        switch kind {
        case .text(let text):
            return text
        case .textWithCard(let text, _):
            return text
        case .card:
            return ""
        }
    }
    
    // Convenience accessor for agent card (when kind is .textWithCard)
    var agentCard: AgentCard? {
        if case .textWithCard(_, let card) = kind {
            return card
        }
        return nil
    }
}
