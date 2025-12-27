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
    
    // Card initializer
    init(id: UUID = UUID(), role: String, card: ChatCard, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.kind = .card(card)
        self.createdAt = createdAt
    }
    
    // Convenience accessor for text (when kind is .text)
    var text: String {
        if case .text(let text) = kind {
            return text
        }
        return ""
    }
}
