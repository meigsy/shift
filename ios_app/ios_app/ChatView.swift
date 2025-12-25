//
//  ChatView.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            messagesList
            inputSection
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chatViewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chatViewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: chatViewModel.messages.count) { _, _ in
                if let lastMessage = chatViewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Start a conversation")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Ask SHIFT about your health and wellness")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var inputSection: some View {
        VStack(spacing: 0) {
            if let errorMessage = chatViewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
            
            HStack(spacing: 12) {
                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(chatViewModel.isLoading)
                    .onChange(of: inputText) { oldValue, newValue in
                        // Detect Enter key press (newline added) and send message
                        if newValue.hasSuffix("\n") && !oldValue.hasSuffix("\n") {
                            // Remove the newline and send
                            inputText = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !inputText.isEmpty && !chatViewModel.isLoading {
                                sendMessage()
                            } else {
                                // If empty after trim, just remove the newline
                                inputText = oldValue
                            }
                        }
                    }
                
                Button {
                    sendMessage()
                } label: {
                    if chatViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatViewModel.isLoading)
            }
            .padding()
            .background(Color(.systemBackground))
        }
    }
    
    private func sendMessage() {
        let text = inputText
        inputText = ""
        isInputFocused = false
        
        Task {
            await chatViewModel.sendMessage(text)
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
            }
            
            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                Group {
                    if let attributedString = try? AttributedString(markdown: message.text) {
                        Text(attributedString)
                    } else {
                        Text(message.text)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    message.role == "user"
                        ? Color.blue
                        : Color(.secondarySystemBackground)
                )
                .foregroundStyle(
                    message.role == "user"
                        ? .white
                        : .primary
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            
            if message.role != "user" {
                Spacer()
            }
        }
    }
}

