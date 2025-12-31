//
//  ChatCardInlineView.swift
//  ios_app
//
//  Inline card view for chat messages
//

import SwiftUI

struct ChatCardInlineView: View {
    let card: ChatCard
    let onAction: (ActionType) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(card.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                Button {
                    onAction(card.primaryCTA.action)
                } label: {
                    Text(card.primaryCTA.label)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                if let secondaryCTA = card.secondaryCTA {
                    Button {
                        onAction(secondaryCTA.action)
                    } label: {
                        Text(secondaryCTA.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}


