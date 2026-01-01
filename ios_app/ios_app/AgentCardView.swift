//
//  AgentCardView.swift
//  ios_app
//
//  Created by SHIFT on 12/31/25.
//

import SwiftUI

struct AgentCardView: View {
    let card: AgentCard
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Card content
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let body = card.body {
                    Text(body)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Action button
            Button(action: onTap) {
                HStack {
                    Text(actionButtonText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(UIColor.systemGray6))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    private var actionButtonText: String {
        switch card.action.type {
        case "full_screen_flow":
            return "Learn More"
        case "chat_prompt":
            return "Continue"
        default:
            return "Open"
        }
    }
}

