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
    var onOpenExperience: ((ExperienceID) -> Void)?
    @State private var showSettings: Bool = false
    @State private var isResetting: Bool = false
    @State private var resetError: String?
    
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
    }
    
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            newChatSection
            Divider()
            pastChatsSection
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
              let service = interactionService else {
            return
        }
        
        // Fire-and-forget: record flow_requested event (non-blocking)
        Task {
            do {
                try await service.recordFlowEvent(
                    eventType: "flow_requested",
                    userId: userId,
                    payload: [
                        "flow_id": GettingStartedFlow.flowId,
                        "flow_version": GettingStartedFlow.version
                    ]
                )
            } catch {
                print("❌ Failed to record flow_requested event: \(error.localizedDescription)")
            }
        }
        
        // Immediately open experience (don't wait for server response)
        onOpenExperience?(.onboarding)
        
        // Close side panel
        withAnimation {
            isOpen = false
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
        // #region agent log
        let logEntry1: [String: Any] = [
            "location": "SidePanelOverlay.swift:320",
            "message": "refreshContext called - fetching context directly",
            "data": [:],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "C"
        ]
        if let logData = try? JSONSerialization.data(withJSONObject: logEntry1),
           let logStr = String(data: logData, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        // Post notification to refresh context (HomeView listens to this if it exists)
        NotificationCenter.default.post(name: .contextRefreshNeeded, object: nil)
        
        // Also fetch context directly and route chat_card interventions to ChatView
        // (since SidePanelOverlay is in ChatView's hierarchy, not HomeView's)
        if let contextService = contextService {
            do {
                let payload = try await contextService.fetchContext()
                
                // #region agent log
                let logEntry2: [String: Any] = [
                    "location": "SidePanelOverlay.swift:335",
                    "message": "Context fetched directly - FULL DETAILS",
                    "data": [
                        "interventionsCount": payload.interventions.count,
                        "chatCardCount": payload.interventions.filter { $0.surface == "chat_card" }.count,
                        "allInterventions": payload.interventions.map { [
                            "key": $0.interventionKey,
                            "surface": $0.surface,
                            "title": $0.title
                        ]}
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "C"
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry2),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                
                // Route chat_card interventions to ChatView
                let chatCardInterventions = payload.interventions.filter { $0.surface == "chat_card" }
                
                // #region agent log
                let logEntry3: [String: Any] = [
                    "location": "SidePanelOverlay.swift:468",
                    "message": "Filtering chat_card interventions",
                    "data": [
                        "totalInterventions": payload.interventions.count,
                        "chatCardCount": chatCardInterventions.count,
                        "chatCardKeys": chatCardInterventions.map { $0.interventionKey }
                    ],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "C"
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry3),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
                
                for intervention in chatCardInterventions {
                    // Encode intervention as JSON data to pass through NotificationCenter
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    if let jsonData = try? encoder.encode(intervention),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        // #region agent log
                        let logEntry4: [String: Any] = [
                            "location": "SidePanelOverlay.swift:486",
                            "message": "Posting chatCardInterventionReceived notification",
                            "data": [
                                "interventionKey": intervention.interventionKey,
                                "interventionInstanceId": intervention.interventionInstanceId,
                                "jsonStringLength": jsonString.count
                            ],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "C"
                        ]
                        if let logData = try? JSONSerialization.data(withJSONObject: logEntry4),
                           let logStr = String(data: logData, encoding: .utf8) {
                            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                        }
                        // #endregion
                        
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .chatCardInterventionReceived,
                                object: nil,
                                userInfo: ["intervention_json": jsonString]
                            )
                        }
                    } else {
                        // #region agent log
                        let logEntry5: [String: Any] = [
                            "location": "SidePanelOverlay.swift:506",
                            "message": "Failed to encode intervention as JSON",
                            "data": ["interventionKey": intervention.interventionKey],
                            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                            "sessionId": "debug-session",
                            "runId": "run1",
                            "hypothesisId": "C"
                        ]
                        if let logData = try? JSONSerialization.data(withJSONObject: logEntry5),
                           let logStr = String(data: logData, encoding: .utf8) {
                            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                        }
                        // #endregion
                    }
                }
            } catch {
                // #region agent log
                let logEntry3: [String: Any] = [
                    "location": "SidePanelOverlay.swift:357",
                    "message": "Failed to fetch context",
                    "data": ["error": error.localizedDescription],
                    "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                    "sessionId": "debug-session",
                    "runId": "run1",
                    "hypothesisId": "C"
                ]
                if let logData = try? JSONSerialization.data(withJSONObject: logEntry3),
                   let logStr = String(data: logData, encoding: .utf8) {
                    try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
                }
                // #endregion
            }
        }
        
    }
}

