//
//  ChatComposerBar.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct ChatComposerBar: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @Binding var draftText: String
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = chatViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            
            HStack(spacing: 12) {
                TextField("Type a message...", text: $draftText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .disabled(chatViewModel.isLoading)
                    .submitLabel(.send)
                    .onSubmit {
                        send()
                    }
                
                Button {
                    send()
                } label: {
                    if chatViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatViewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
    
    private func send() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !chatViewModel.isLoading else { return }
        
        draftText = ""
        isInputFocused = false
        
        Task {
            await chatViewModel.sendMessage(text)
        }
    }
}

