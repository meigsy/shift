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
    @Binding var activeExperience: ExperienceID?
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
                        testToolEvent()
                    } label: {
                        Image(systemName: "bolt.circle")
                    }
                }
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
            .onReceive(NotificationCenter.default.publisher(for: .chatCardInterventionReceived)) { notification in
                // #region agent log
                let logEntry: [String: Any] = [
                    "location": "ChatView.swift:92",
                    "message": "chatCardInterventionReceived notification received",
                    "data": [
                        "hasUserInfo": notification.userInfo != nil,
                        "userInfoKeys": notification.userInfo?.keys.map { String(describing: $0) } ?? []
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "B"
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                
                // Decode intervention from JSON string
                guard let jsonString = notification.userInfo?["intervention_json"] as? String,
                      let jsonData = jsonString.data(using: .utf8),
                      let intervention = try? JSONDecoder().decode(Intervention.self, from: jsonData) else {
                    // #region agent log
                    let logEntry2: [String: Any] = [
                        "location": "ChatView.swift:108",
                        "message": "Failed to decode Intervention from notification JSON",
                        "data": [
                            "hasUserInfo": notification.userInfo != nil,
                            "hasJsonString": notification.userInfo?["intervention_json"] != nil
                        ],
                        "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                        "sessionId": "debug-session",
                        "runId": "run1",
                        "hypothesisId": "B"
                    ]
                    if let logData = try? JSONSerialization.data(withJSONObject: logEntry2),
                       let logStr = String(data: logData, encoding: .utf8) {
                        try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                    }
                    // #endregion
                    return
                }
                handleChatCardIntervention(intervention)
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
    
    // MARK: - Chat Card Handling
    
    private func handleChatCardIntervention(_ intervention: Intervention) {
        // #region agent log
        let logEntry1: [String: Any] = [
            "location": "ChatView.swift:171",
            "message": "handleChatCardIntervention called",
            "data": [
                "interventionKey": intervention.interventionKey,
                "interventionInstanceId": intervention.interventionInstanceId,
                "title": intervention.title,
                "surface": intervention.surface
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B"
        ]
        if let logData = try? JSONSerialization.data(withJSONObject: logEntry1),
           let logStr = String(data: logData, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        // Convert Intervention to ChatCard
        let card: ChatCard
        
        if intervention.interventionKey == GettingStartedFlow.interventionKey {
            // #region agent log
            let logEntry2: [String: Any] = [
                "location": "ChatView.swift:175",
                "message": "Creating getting_started card with onboarding action",
                "data": ["interventionKey": intervention.interventionKey],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "B"
            ]
            if let logData = try? JSONSerialization.data(withJSONObject: logEntry2),
               let logStr = String(data: logData, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            
            // Getting started card opens onboarding experience
            card = ChatCard(
                id: intervention.interventionInstanceId,
                title: intervention.title,
                body: intervention.body,
                primaryCTA: CardAction(
                    label: "Start",
                    action: .openExperience(.onboarding)
                )
            )
        } else {
            // Generic chat card - could inject prompt or open detail view
            card = ChatCard(
                id: intervention.interventionInstanceId,
                title: intervention.title,
                body: intervention.body,
                primaryCTA: CardAction(
                    label: "Learn more",
                    action: .injectPrompt("Tell me more about: \(intervention.title)")
                )
            )
        }
        
        // Insert card into chat
        chatViewModel.insertCard(card)
        
        // #region agent log
        let logEntry3: [String: Any] = [
            "location": "ChatView.swift:200",
            "message": "ChatCard inserted into chatViewModel",
            "data": [
                "cardId": card.id,
                "title": card.title,
                "messagesCount": chatViewModel.messages.count
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B"
        ]
        if let logData = try? JSONSerialization.data(withJSONObject: logEntry3),
           let logStr = String(data: logData, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        // Log "shown" event
        if let service = makeInteractionService() {
            Task {
                do {
                    try await service.recordInteraction(
                        intervention: intervention,
                        eventType: "shown",
                        userId: intervention.userId
                    )
                } catch {
                    print("❌ Failed to log shown event: \(error.localizedDescription)")
                }
            }
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
    private func testToolEvent() {
        print("🧪 Testing ToolEventService...")
        
        Task {
            do {
                let apiClient = ApiClient(
                    baseURL: ios_appApp.CONVERSATIONAL_AGENT_BASE_URL,
                    idToken: authViewModel.idToken
                )
                
                let toolEventService = ToolEventService(
                    apiClient: apiClient,
                    chatViewModel: chatViewModel
                )
                
                let response = try await toolEventService.sendToolEvent(
                    type: "app_opened",
                    context: "Debug test from ChatView toolbar"
                )
                
                print("✅ Tool event test successful! Response: \(response ?? "nil")")
                
            } catch {
                print("❌ Tool event test failed: \(error)")
            }
        }
    }
    
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
