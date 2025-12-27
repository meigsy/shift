//
//  ChatCard.swift
//  ios_app
//
//  Card models for inline chat cards (MVP)
//

import Foundation

struct ChatCard: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
    let primaryCTA: CardAction
    let secondaryCTA: CardAction?
    let createdAt: Date
    
    init(
        id: String,
        title: String,
        body: String,
        primaryCTA: CardAction,
        secondaryCTA: CardAction? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.primaryCTA = primaryCTA
        self.secondaryCTA = secondaryCTA
        self.createdAt = createdAt
    }
}

struct CardAction: Equatable {
    let label: String
    let action: ActionType
    
    init(label: String, action: ActionType) {
        self.label = label
        self.action = action
    }
}

enum ActionType: Equatable {
    case injectPrompt(String)
    case openExperience(ExperienceID)
}

enum ExperienceID: Equatable, Identifiable {
    case onboarding
    case breathing60s
    
    var id: String {
        switch self {
        case .onboarding: return "onboarding"
        case .breathing60s: return "breathing60s"
        }
    }
}

