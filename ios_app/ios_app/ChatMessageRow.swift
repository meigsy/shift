//
//  ChatMessageRow.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct ChatMessageRow: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == "user" {
                Spacer()
            }
            
            Group {
                if let attributedString = try? AttributedString(markdown: message.text) {
                    Text(attributedString)
                } else {
                    Text(message.text)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: message.role == "assistant" ? .infinity : nil, alignment: .leading)
            .background(
                message.role == "user"
                    ? Color(.secondarySystemBackground)
                    : Color.clear
            )
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if message.role == "user" {
                Spacer()
            }
        }
    }
}

