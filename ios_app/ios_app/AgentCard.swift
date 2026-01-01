//
//  AgentCard.swift
//  ios_app
//
//  Created by SHIFT on 12/31/25.
//

import Foundation

struct AgentCard: Codable, Identifiable, Equatable {
    var id = UUID()
    let type: String
    let title: String
    let body: String?
    let action: AgentCardAction
    
    enum CodingKeys: String, CodingKey {
        case type, title, body, action
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        action = try container.decode(AgentCardAction.self, forKey: .action)
        id = UUID()  // Generate new ID for each decoded card
    }
    
    init(type: String, title: String, body: String?, action: AgentCardAction) {
        self.type = type
        self.title = title
        self.body = body
        self.action = action
        self.id = UUID()
    }
    
    static func == (lhs: AgentCard, rhs: AgentCard) -> Bool {
        lhs.type == rhs.type && lhs.title == rhs.title && lhs.body == rhs.body && lhs.action == rhs.action
    }
}

struct AgentCardAction: Codable, Equatable {
    let type: String  // "full_screen_flow", "chat_prompt"
    let flowId: String?
    let prompt: String?
    
    enum CodingKeys: String, CodingKey {
        case type
        case flowId = "flow_id"
        case prompt
    }
}

