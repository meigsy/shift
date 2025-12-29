//
//  SidePanelOverlay.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct SidePanelOverlay: View {
    @Binding var isOpen: Bool
    let chatViewModel: ChatViewModel
    let authViewModel: AuthViewModel
    @State private var showSettings: Bool = false
    @State private var isResetting: Bool = false
    @State private var resetError: String?
    @State private var savedInterventions: [String] = []
    @State private var isLoadingSaved: Bool = false
    
    private let panelWidth: CGFloat = 280
    
    private var interactionService: InteractionService? {
        guard authViewModel.user?.userId != nil else { return nil }
        let apiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        return InteractionService(apiClient: apiClient)
    }
    
    private var contextService: ContextService? {
        let apiClient = ApiClient(
            baseURL: authViewModel.backendBaseURL,
            idToken: authViewModel.idToken
        )
        apiClient.setToken(authViewModel.idToken)
        return ContextService(apiClient: apiClient)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isOpen = false
                        }
                    }
                
                sidePanel
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isOpen)
        .onChange(of: isOpen) { _, isOpen in
            if isOpen {
                Task {
                    await loadSavedInterventions()
                }
            }
        }
    }
    
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            newChatSection
            Divider()
            pastChatsSection
            Divider()
            savedInterventionsSection
            Divider()
            Spacer()
            Divider()
            userMenuSection
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(Color(.systemBackground))
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation {
                            isOpen = false
                        }
                    }
                }
        )
    }
    
    private var headerSection: some View {
        HStack {
            Text("SHIFT")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button {
                withAnimation {
                    isOpen = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var newChatSection: some View {
        Button {
            chatViewModel.startNewChat()
            withAnimation {
                isOpen = false
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("New Chat")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .buttonStyle(.plain)
    }
    
    private var pastChatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past Chats")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
    
    private var savedInterventionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            if isLoadingSaved {
                ProgressView()
                    .padding(.horizontal)
                    .padding(.bottom)
            } else if savedInterventions.isEmpty {
                Text("No saved interventions")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal)
                    .padding(.bottom)
            } else {
                ForEach(savedInterventions, id: \.self) { interventionKey in
                    Button {
                        handleRequestSavedIntervention(interventionKey: interventionKey)
                    } label: {
                        HStack {
                            Image(systemName: "bookmark.fill")
                            Text(interventionKey)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
            }
        }
    }
    
    private var userMenuSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("User Menu")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            Button {
                handleAboutShift()
            } label: {
                HStack {
                    Image(systemName: "info.circle")
                    Text("About SHIFT")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
            
            Button {
                withAnimation {
                    isOpen = false
                }
                showSettings = true
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel)
            }
            
            Button {
                handleResetData()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset my data")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
            .disabled(isResetting)
            
            if let error = resetError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            Button {
                authViewModel.signOut()
                withAnimation {
                    isOpen = false
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.square")
                    Text("Logout")
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom)
    }
    
    // MARK: - Actions
    
    private func handleAboutShift() {
        guard let userId = authViewModel.user?.userId,
              let service = interactionService else { return }
        
        Task {
            do {
                // Post flow_requested event
                try await service.recordFlowEvent(
                    eventType: "flow_requested",
                    userId: userId,
                    payload: ["flow_id": GettingStartedFlow.flowId]
                )
                
                // Refresh context to get getting_started intervention
                await refreshContext()
                
                await MainActor.run {
                    withAnimation {
                        isOpen = false
                    }
                }
            } catch {
                print("❌ Failed to request About SHIFT: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleResetData() {
        guard authViewModel.user?.userId != nil,
              let service = interactionService else { return }
        
        isResetting = true
        resetError = nil
        
        Task {
            do {
                // Post reset request
                try await service.resetUserData(scope: "all")
                
                // Refresh context to see getting_started again
                await refreshContext()
                
                await MainActor.run {
                    isResetting = false
                    withAnimation {
                        isOpen = false
                    }
                }
            } catch {
                await MainActor.run {
                    isResetting = false
                    resetError = "Failed to reset: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func refreshContext() async {
        // Post notification to refresh context (HomeView listens to this)
        NotificationCenter.default.post(name: .contextRefreshNeeded, object: nil)
        await loadSavedInterventions()
    }
    
    private func loadSavedInterventions() async {
        guard let service = contextService else { return }
        
        await MainActor.run {
            isLoadingSaved = true
        }
        
        do {
            let payload = try await service.fetchContext()
            await MainActor.run {
                self.savedInterventions = payload.savedInterventions ?? []
                self.isLoadingSaved = false
            }
        } catch {
            print("❌ Failed to load saved interventions: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoadingSaved = false
            }
        }
    }
    
    private func handleRequestSavedIntervention(interventionKey: String) {
        guard let userId = authViewModel.user?.userId,
              let service = interactionService else { return }
        
        Task {
            do {
                // Post intervention_requested event
                try await service.recordFlowEvent(
                    eventType: "intervention_requested",
                    userId: userId,
                    payload: ["intervention_key": interventionKey]
                )
                
                // Refresh context to get the intervention instance
                await refreshContext()
                
                await MainActor.run {
                    withAnimation {
                        isOpen = false
                    }
                }
            } catch {
                print("❌ Failed to request saved intervention: \(error.localizedDescription)")
            }
        }
    }
}

