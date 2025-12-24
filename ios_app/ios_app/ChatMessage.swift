//
//  ChatMessage.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import Foundation

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: String  // "user" | "assistant" | "system"
    let text: String
    let createdAt: Date
    
    init(id: UUID = UUID(), role: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

