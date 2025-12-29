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
}


