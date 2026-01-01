//
//  AppShellView.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct AppShellView: View {
    let authViewModel: AuthViewModel
    let conversationalAgentBaseURL: String
    
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var isSidePanelOpen: Bool = false
    @State private var activeExperience: ExperienceID? = nil
    @State private var interventions: [Intervention] = []
    @State private var contextLoaded: Bool = false
    
    private var contextService: ContextService {
        let apiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        return ContextService(apiClient: apiClient)
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ChatView(
                    chatViewModel: chatViewModel,
                    authViewModel: authViewModel,
                    activeExperience: $activeExperience
                )
                
                SidePanelOverlay(
                    isOpen: $isSidePanelOpen,
                    chatViewModel: chatViewModel,
                    authViewModel: authViewModel,
                    onOpenExperience: { activeExperience = $0 }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            isSidePanelOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
            .task {
                // #region agent log
                let logEntry: [String: Any] = [
                    "location": "AppShellView.swift:56",
                    "message": ".task TRIGGERED",
                    "data": [
                        "timestamp": Date().timeIntervalSince1970
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "D",
                    "timestamp": Date().timeIntervalSince1970
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? (logStr + "\n").appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                
                await loadContextOnStartup()
                await sendAppLaunchEvent()
            }
        }
    }
    
    private func loadContextOnStartup() async {
        guard !contextLoaded else { return }
        
        do {
            let payload = try await contextService.fetchContext()
            
            await MainActor.run {
                self.interventions = payload.interventions
                self.contextLoaded = true
            }
            
            // REMOVED: Auto-present logic for getting_started
            // The new card-based system handles this via sendAppLaunchEvent()
            // which returns a "Welcome to SHIFT" card that user can tap.
            // This prevents the slideshow from covering HealthKit permission dialogs.
            
        } catch {
            print("❌ Failed to load context: \(error.localizedDescription)")
        }
    }
    
    private func sendAppLaunchEvent() async {
        // #region agent log
        let logEntry1: [String: Any] = [
            "location": "AppShellView.swift:94",
            "message": "sendAppLaunchEvent CALLED",
            "data": [
                "timestamp": Date().timeIntervalSince1970
            ],
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B",
            "timestamp": Date().timeIntervalSince1970
        ]
        if let logData = try? JSONSerialization.data(withJSONObject: logEntry1),
           let logStr = String(data: logData, encoding: .utf8) {
            try? (logStr + "\n").appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        // Determine if first launch
        let hasLaunchedKey = "has_launched_before"
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: hasLaunchedKey)
        let eventType = hasLaunchedBefore ? "app_opened" : "app_opened_first_time"
        
        print("📱 Sending app launch event: \(eventType)")
        
        // Create ToolEventService
        let apiClient = ApiClient(
            baseURL: conversationalAgentBaseURL,
            idToken: authViewModel.idToken
        )
        let toolEventService = ToolEventService(
            apiClient: apiClient,
            chatViewModel: chatViewModel
        )
        
        do {
            let (response, card) = try await toolEventService.sendToolEvent(
                type: eventType,
                context: "App launched"
            )
            
            // #region agent log
            let logEntry2: [String: Any] = [
                "location": "AppShellView.swift:117",
                "message": "AppShellView AFTER sendToolEvent",
                "data": [
                    "hasResponse": response != nil,
                    "responseLength": response?.count ?? 0,
                    "hasCard": card != nil,
                    "currentMessageCount": chatViewModel.messages.count
                ],
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "A",
                "timestamp": Date().timeIntervalSince1970
            ]
            if let logData = try? JSONSerialization.data(withJSONObject: logEntry2),
               let logStr = String(data: logData, encoding: .utf8) {
                try? (logStr + "\n").appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            
            // If we received a card, inject it into chat with the response
            if let card = card {
                await MainActor.run {
                    chatViewModel.injectMessage(role: "assistant", text: response ?? "", card: card)
                }
                print("📇 Agent card injected into chat: \(card.title)")
                
                // #region agent log
                let logEntry3: [String: Any] = [
                    "location": "AppShellView.swift:135",
                    "message": "AppShellView INJECTED message with card",
                    "data": [
                        "cardTitle": card.title,
                        "messageCount": chatViewModel.messages.count
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "A",
                    "timestamp": Date().timeIntervalSince1970
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry3),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? (logStr + "\n").appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
            } else if let response = response, !response.isEmpty {
                // Just text response, no card
                await MainActor.run {
                    chatViewModel.injectMessage(role: "assistant", text: response)
                }
                print("💬 Agent response injected into chat")
                
                // #region agent log
                let logEntry4: [String: Any] = [
                    "location": "AppShellView.swift:151",
                    "message": "AppShellView INJECTED text-only message",
                    "data": [
                        "messageCount": chatViewModel.messages.count
                    ],
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "A",
                    "timestamp": Date().timeIntervalSince1970
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry4),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? (logStr + "\n").appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
            }
            
            // Mark that app has launched (only after first successful event)
            if !hasLaunchedBefore {
                UserDefaults.standard.set(true, forKey: hasLaunchedKey)
                print("✅ First launch recorded")
            }
            
        } catch {
            print("❌ Failed to send app launch event: \(error)")
        }
    }
}


