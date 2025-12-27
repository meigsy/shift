//
//  ChatMessageRow.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage
    let onCardAction: ((ActionType) -> Void)?
    
    init(message: ChatMessage, onCardAction: ((ActionType) -> Void)? = nil) {
        self.message = message
        self.onCardAction = onCardAction
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" {
                Spacer()
            }
            
            Group {
                switch message.kind {
                case .text(let text):
                    textBubble(text)
                case .card(let card):
                    if let onCardAction = onCardAction {
                        ChatCardInlineView(card: card, onAction: onCardAction)
                    } else {
                        ChatCardInlineView(card: card, onAction: { _ in })
                    }
                }
            }
            .frame(maxWidth: message.role == "user" ? nil : .infinity, alignment: message.role == "user" ? .trailing : .leading)
            
            if message.role == "user" {
                Spacer()
            }
        }
    }
    
    @ViewBuilder
    private func textBubble(_ text: String) -> some View {
        Group {
            if let attributedString = try? AttributedString(markdown: text) {
                Text(attributedString)
            } else {
                Text(text)
            }
        }
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            message.role == "user"
                ? Color(.secondarySystemBackground)
                : Color.clear
        )
        .foregroundStyle(.primary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
