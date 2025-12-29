//
//  MainView.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import SwiftUI
import Combine

struct MainView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @EnvironmentObject var healthKit: HealthKitManager
    
    // Intervention polling
    @StateObject private var interventionRouter = InterventionRouter()
    @State private var interventionPoller: InterventionPoller?
    @State private var displayedBanners: [Intervention] = []
    @State private var interventionBaseURL: String = "https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http"
    @State private var interactionService: InteractionService?
    // Navigation state for banner tap → detail
    @State private var selectedInterventionForDetail: Intervention?
    @State private var contextService: ContextService?
    
    var body: some View {
        mainContent
            .overlay(alignment: .top) {
                bannerOverlay
            }
    }
    
    private var mainContent: some View {
        NavigationStack {
            VStack(spacing: 0) {
                userInfoSection
                HomeView(
                    authViewModel: authViewModel,
                    contextService: contextService ?? makeContextService(),
                    interactionService: interactionService
                )
            }
            .navigationTitle("SHIFT")
            .task {
                await taskHandler()
            }
            .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
                handleAuthChange(isAuthenticated)
            }
            .onChange(of: authViewModel.idToken) { _, _ in
                handleTokenChange()
            }
            .onChange(of: authViewModel.user) { _, newUser in
                if newUser != nil {
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    print("👤 [\(timestamp)] User object set - userId: \(newUser?.userId ?? "nil"), triggering polling setup")
                    setupInterventionServices()
                    setupInterventionPolling()
                }
            }
            .onChange(of: healthKit.isAuthorized) { _, authorized in
                handleHealthKitAuthChange(authorized)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                handleForeground()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                handleBackground()
            }
            .onReceive(NotificationCenter.default.publisher(for: .healthDataSyncCompleted)) { _ in
                handleSyncCompleted()
            }
            .onReceive(interventionRouter.$newIntervention.compactMap { $0 }) { intervention in
                handleNewIntervention(intervention)
            }
        }
    }
    
    private var bannerOverlay: some View {
        VStack(spacing: 8) {
            ForEach(displayedBanners) { intervention in
                InterventionBanner(
                    intervention: intervention,
                    interactionService: interactionService,
                    userId: authViewModel.user?.userId ?? "",
                    onDismiss: {
                        displayedBanners.removeAll { $0.id == intervention.id }
                    },
                    onTap: {
                        // Banner tap opens detail (does not log "tapped")
                        selectedInterventionForDetail = intervention
                    }
                )
            }
        }
        .padding(.top, 8)
        .sheet(item: $selectedInterventionForDetail) { intervention in
            NavigationStack {
                InterventionDetailView(
                    intervention: intervention,
                    stateEstimate: nil, // Could fetch from context if needed
                    interactionService: interactionService,
                    userId: authViewModel.user?.userId ?? ""
                )
            }
        }
    }
    
    private var userInfoSection: some View {
        VStack {
            if let user = authViewModel.user {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("User ID", systemImage: "person.circle")
                        Spacer()
                        Text(user.userId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let email = user.email {
                        HStack {
                            Label("Email", systemImage: "envelope")
                            Spacer()
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Button {
                        authViewModel.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                            .foregroundStyle(.red)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func taskHandler() async {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🚀 [\(timestamp)] MainView.taskHandler() - setting up polling")
        
        setupInterventionServices()
        setupInterventionPolling()
    }
    
    private func handleAuthChange(_ isAuthenticated: Bool) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🔐 [\(timestamp)] Auth changed - isAuthenticated: \(isAuthenticated), userId: \(authViewModel.user?.userId ?? "nil")")
        
        if isAuthenticated {
            setupInterventionServices()
            setupInterventionPolling()
        } else {
            interventionPoller?.stopPolling()
            interventionPoller = nil
            displayedBanners.removeAll()
        }
    }
    
    private func handleTokenChange() {
        if let poller = interventionPoller {
            poller.stopPolling()
            interventionPoller = nil
            setupInterventionPolling()
        }
    }
    
    private func handleHealthKitAuthChange(_ authorized: Bool) {
        // Health data is not required for MVP Home UX; keep hooks for future use.
        _ = authorized
    }
    
    private func handleForeground() {
        interventionPoller?.startPolling()
    }
    
    private func handleBackground() {
        interventionPoller?.stopPolling()
    }
    
    private func handleSyncCompleted() {
        // Hook preserved for future metrics, no-op for MVP Home.
    }
    
    private func handleNewIntervention(_ intervention: Intervention) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🎨 [\(timestamp)] Displaying banner for intervention: \(intervention.title)")
        displayedBanners.append(intervention)
        interventionRouter.newIntervention = nil
        
        // Banner logs "shown" in its onAppear with deduplication
    }
    
    private func setupInterventionServices() {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🧩 [\(timestamp)] setupInterventionServices() called - isAuthenticated: \(authViewModel.isAuthenticated), userId: \(authViewModel.user?.userId ?? "nil")")
        
        guard authViewModel.isAuthenticated else {
            print("⚠️ [\(timestamp)] Cannot setup services - not authenticated")
            return
        }
        
        guard authViewModel.user?.userId != nil else {
            print("⚠️ [\(timestamp)] Cannot setup services - no user ID")
            return
        }
        
        // Create API client for watch_events backend (used by both interaction and context services)
        let watchEventsApiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        watchEventsApiClient.setToken(authViewModel.idToken)
        
        // Create interaction service (for tracking user interactions)
        self.interactionService = InteractionService(apiClient: watchEventsApiClient)
        
        // Context service for /context (Home screen)
        self.contextService = ContextService(apiClient: watchEventsApiClient)
    }
    
    private func setupInterventionPolling() {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🔍 [\(timestamp)] setupInterventionPolling() called - isAuthenticated: \(authViewModel.isAuthenticated), userId: \(authViewModel.user?.userId ?? "nil"), poller exists: \(interventionPoller != nil)")
        
        guard authViewModel.isAuthenticated else {
            print("⚠️ [\(timestamp)] Cannot setup polling - not authenticated")
            return
        }
        
        guard let userId = authViewModel.user?.userId else {
            print("⚠️ [\(timestamp)] Cannot setup polling - no user ID")
            return
        }
        
        guard interventionPoller == nil else {
            print("ℹ️ [\(timestamp)] Polling already setup, skipping")
            return
        }
        
        // Create API client for intervention service (separate from watch_events backend)
        let apiClient = ApiClient(
            baseURL: interventionBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        
        // Create intervention service (for fetching interventions)
        let interventionService = InterventionService(apiClient: apiClient)
        
        // Create and start poller
        let poller = InterventionPoller(
            interventionService: interventionService,
            router: interventionRouter,
            userId: userId
        )
        
        interventionPoller = poller
        poller.startPolling()
        
        print("✅ [\(timestamp)] Intervention polling setup for user: \(userId)")
    }
    
    private func makeContextService() -> ContextService {
        let apiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        return ContextService(apiClient: apiClient)
    }
}

#Preview {
    MainView(authViewModel: AuthViewModel())
}


