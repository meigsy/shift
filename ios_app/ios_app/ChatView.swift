//
//  ChatView.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct ComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct ChatView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @State private var draftText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var composerHeight: CGFloat = 0
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chatViewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chatViewModel.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    
                    // Reserve space for composer so nothing can go underneath it
                    Color.clear
                        .frame(height: composerHeight + 16)
                        .id("BOTTOM")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if !chatViewModel.messages.isEmpty {
                    DispatchQueue.main.async { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                }
            }
            .onChange(of: chatViewModel.messages.count) { _, _ in
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo("BOTTOM", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                ChatComposerBar(
                    chatViewModel: chatViewModel,
                    draftText: $draftText,
                    isInputFocused: $isInputFocused
                )
                .background(.ultraThinMaterial)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ComposerHeightKey.self, value: geo.size.height)
                    }
                )
            }
            .onPreferenceChange(ComposerHeightKey.self) { newHeight in
                if abs(newHeight - composerHeight) > 0.5 { composerHeight = newHeight }
            }
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
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
}

