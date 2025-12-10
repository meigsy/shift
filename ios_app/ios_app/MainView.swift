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
    
    @State private var heartRates: [HeartRateSample] = []
    @State private var hrvSamples: [HRVSample] = []
    @State private var todaySteps: Int = 0
    @State private var isLoading = false
    
    // Intervention polling
    @StateObject private var interventionRouter = InterventionRouter()
    @State private var interventionPoller: InterventionPoller?
    @State private var displayedBanners: [Intervention] = []
    @State private var interventionBaseURL: String = "https://us-central1-shift-dev-478422.cloudfunctions.net/intervention-selector-http"
    @State private var interactionService: InteractionService?
    
    var body: some View {
        mainContent
            .overlay(alignment: .top) {
                bannerOverlay
            }
    }
    
    private var mainContent: some View {
        NavigationStack {
            listContent
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
    
    private var listContent: some View {
        List {
            userInfoSection
            authorizationSection
            if healthKit.isAuthorized {
                dataSections
            }
        }
    }
    
    private var bannerOverlay: some View {
        VStack(spacing: 8) {
            ForEach(displayedBanners) { intervention in
                InterventionBanner(
                    intervention: intervention,
                    interactionService: interactionService,
                    userId: authViewModel.user?.userId ?? ""
                ) {
                    displayedBanners.removeAll { $0.id == intervention.id }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private var userInfoSection: some View {
        Group {
            if let user = authViewModel.user {
                Section {
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
                } header: {
                    Text("Account")
                }
            }
        }
    }
    
    private var authorizationSection: some View {
        Section {
            if !healthKit.isHealthKitAvailable {
                Label("HealthKit not available", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else if healthKit.isAuthorized {
                Label("HealthKit connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    Task {
                        await healthKit.requestAuthorization()
                    }
                } label: {
                    Label("Connect HealthKit", systemImage: "heart.circle")
                }
            }
            
            if let error = healthKit.authorizationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Connection")
        }
    }
    
    private var dataSections: some View {
        Group {
            Section {
                HStack {
                    Label("Steps today", systemImage: "figure.walk")
                    Spacer()
                    Text("\(todaySteps)")
                        .fontWeight(.semibold)
                }
            } header: {
                Text("Activity")
            }
            
            Section {
                if heartRates.isEmpty {
                    Text("No heart rate data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(heartRates.prefix(5)) { sample in
                        HStack {
                            Label("\(Int(sample.bpm)) bpm", systemImage: "heart.fill")
                                .foregroundStyle(.red)
                            Spacer()
                            Text(sample.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Heart Rate (last 24h)")
            }
            
            Section {
                if hrvSamples.isEmpty {
                    Text("No HRV data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hrvSamples.prefix(5)) { sample in
                        HStack {
                            Label("\(Int(sample.sdnn)) ms", systemImage: "waveform.path.ecg")
                                .foregroundStyle(.purple)
                            Spacer()
                            Text(sample.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("HRV (last 7 days)")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func taskHandler() async {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🚀 [\(timestamp)] MainView.taskHandler() - setting up polling")
        
        if healthKit.isAuthorized {
            await fetchAllData()
        }
        setupInterventionPolling()
    }
    
    private func handleAuthChange(_ isAuthenticated: Bool) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🔐 [\(timestamp)] Auth changed - isAuthenticated: \(isAuthenticated), userId: \(authViewModel.user?.userId ?? "nil")")
        
        if isAuthenticated {
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
        if authorized {
            Task {
                await fetchAllData()
            }
        }
    }
    
    private func handleForeground() {
        Task {
            await fetchAllData()
        }
        interventionPoller?.startPolling()
    }
    
    private func handleBackground() {
        interventionPoller?.stopPolling()
    }
    
    private func handleSyncCompleted() {
        Task {
            await fetchAllData()
        }
    }
    
    private func handleNewIntervention(_ intervention: Intervention) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🎨 [\(timestamp)] Displaying banner for intervention: \(intervention.title)")
        displayedBanners.append(intervention)
        interventionRouter.newIntervention = nil
        
        // Record "shown" interaction
        if let interactionService = interactionService, let userId = authViewModel.user?.userId {
            Task {
                try? await interactionService.recordInteraction(
                    intervention: intervention,
                    eventType: "shown",
                    userId: userId
                )
            }
        }
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
        
        // Create API client for intervention service
        let apiClient = ApiClient(
            baseURL: interventionBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        
        // Create intervention service (for fetching interventions)
        let interventionService = InterventionService(apiClient: apiClient)
        
        // Create interaction service (for tracking user interactions)
        let watchEventsApiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        watchEventsApiClient.setToken(authViewModel.idToken)
        self.interactionService = InteractionService(apiClient: watchEventsApiClient)
        
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
    
    private func fetchAllData() async {
        isLoading = true
        async let hr = healthKit.fetchRecentHeartRates()
        async let hrv = healthKit.fetchRecentHRV()
        async let steps = healthKit.fetchTodaySteps()
        
        heartRates = await hr
        hrvSamples = await hrv
        todaySteps = await steps
        isLoading = false
    }
}

#Preview {
    MainView(authViewModel: AuthViewModel())
}


