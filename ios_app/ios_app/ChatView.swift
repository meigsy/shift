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
    let authViewModel: AuthViewModel
    @State private var draftText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var composerHeight: CGFloat = 0
    @State private var activeExperience: ExperienceID? = nil
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chatViewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(chatViewModel.messages) { message in
                            ChatMessageRow(message: message, onCardAction: handleCardAction)
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
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        insertStressCard()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        insertBreathingCard()
                    } label: {
                        Image(systemName: "wind")
                    }
                }
                #endif
            }
            .fullScreenCover(item: $activeExperience) { experience in
                experienceView(for: experience)
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
    
    // MARK: - Card Actions
    
    private func handleCardAction(_ action: ActionType) {
        switch action {
        case .injectPrompt(let text):
            chatViewModel.injectMessage(role: "assistant", text: text)
        case .openExperience(let experienceId):
            activeExperience = experienceId
        }
    }
    
    // MARK: - Experience Views
    
    @ViewBuilder
    private func experienceView(for experience: ExperienceID) -> some View {
        switch experience {
        case .onboarding:
            OnboardingExperienceView(
                onClose: {
                    activeExperience = nil
                },
                onComplete: {
                    activeExperience = nil
                    // Onboarding completion is now tracked via backend interaction events
                    // Backend will stop showing getting_started after flow_completed event
                    let growPrompt = """
Let's begin with a quick check-in.

G: What's a goal you want to work on this week?
R: Where are you right now (briefly)?
O: What options feel realistic today?
W: What will you do next?
"""
                    chatViewModel.injectMessage(role: "assistant", text: growPrompt)
                },
                interactionService: makeInteractionService(),
                userId: authViewModel.user?.userId ?? ""
            )
        case .breathing60s:
            BreathingExperienceView(
                onClose: {
                    activeExperience = nil
                },
                onComplete: {
                    activeExperience = nil
                    chatViewModel.injectMessage(role: "assistant", text: "Nice. How do you feel now compared to before (0–10)?")
                }
            )
        }
    }
    
    // MARK: - Services
    
    private func makeInteractionService() -> InteractionService? {
        guard authViewModel.user?.userId != nil else { return nil }
        let apiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        return InteractionService(apiClient: apiClient)
    }
    
    #if DEBUG
    private func insertStressCard() {
        let stressCard = ChatCard(
            id: "stress-check-in-v1",
            title: "Quick stress check-in",
            body: "Want to do a quick 10-second check-in?",
            primaryCTA: CardAction(
                label: "Check in",
                action: .injectPrompt("Quick check-in: how stressed do you feel right now (0–10)? What's going on?")
            )
        )
        chatViewModel.insertCard(stressCard)
    }
    
    private func insertBreathingCard() {
        let breathingCard = ChatCard(
            id: "breathing-exercise-v1",
            title: "60-second breathing",
            body: "A quick reset. Want to try it?",
            primaryCTA: CardAction(
                label: "Start",
                action: .openExperience(.breathing60s)
            )
        )
        chatViewModel.insertCard(breathingCard)
    }
    #endif
}
