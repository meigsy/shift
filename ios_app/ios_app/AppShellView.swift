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
            
            // Check for getting_started intervention and auto-present if found
            if let gettingStarted = payload.interventions.first(where: { $0.interventionKey == "getting_started_v1" }) {
                // Auto-present the onboarding flow
                await MainActor.run {
                    activeExperience = .onboarding
                }
            }
            
        } catch {
            print("❌ Failed to load context: \(error.localizedDescription)")
        }
    }
    
    private func sendAppLaunchEvent() async {
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
            
            // If we received a card, inject it into chat with the response
            if let card = card {
                await MainActor.run {
                    chatViewModel.injectMessage(role: "assistant", text: response ?? "", card: card)
                }
                print("📇 Agent card injected into chat: \(card.title)")
            } else if let response = response, !response.isEmpty {
                // Just text response, no card
                await MainActor.run {
                    chatViewModel.injectMessage(role: "assistant", text: response)
                }
                print("💬 Agent response injected into chat")
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


