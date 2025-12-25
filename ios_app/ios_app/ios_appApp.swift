//
//  ios_appApp.swift
//  ios_app
//
//  Created by Sylvester Meighan on 11/25/25.
//

import SwiftUI
import Combine

@main
struct ios_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Base URLs - single canonical location
    static let CONVERSATIONAL_AGENT_BASE_URL = "https://conversational-agent-meqmyk4w5q-uc.a.run.app"  // Deployed Cloud Run URL
    
    // Shared instances
    @StateObject private var healthKitManager = HealthKitManager()
    // Set useMockAuth: true to test without Apple Developer account
    // Set useMockAuth: false for production (requires Apple Developer account)
    @StateObject private var authViewModel = AuthViewModel(
        backendBaseURL: "https://watch-events-meqmyk4w5q-uc.a.run.app",  // Deployed Cloud Run URL
        useMockAuth: true  // Set to false when ready for production
    )
    @StateObject private var syncServiceContainer = SyncServiceContainer()
    private let syncCoordinator = SyncCoordinator()
    
    var body: some Scene {
        WindowGroup {
            ContentView(authViewModel: authViewModel)
                .environmentObject(healthKitManager)
                .onAppear {
                    // Initialize ApiClient with auth token
                    let apiClient = ApiClient(
                        baseURL: authViewModel.backendBaseURL,
                        idToken: authViewModel.idToken
                    )
                    
                    // Initialize syncService with healthKitManager and apiClient
                    syncServiceContainer.initialize(
                        healthKitManager: healthKitManager,
                        apiClient: apiClient
                    )
                    
                    // Start observing HealthKit updates after app appears
                    Task { @MainActor in
                        await setupHealthKitObservers()
                    }
                }
                .onChange(of: authViewModel.idToken) { _, newToken in
                    syncServiceContainer.syncService?.updateToken(newToken)
                }
        }
    }
    
    @MainActor
    private func setupHealthKitObservers() async {
        // Wait for authorization if needed
        if !healthKitManager.isAuthorized && healthKitManager.isHealthKitAvailable {
            await healthKitManager.requestAuthorization()
        }
        
        // Only start observers if authorized
        guard healthKitManager.isAuthorized else {
            print("⏸️ Not starting observers - HealthKit not authorized yet")
            return
        }
        
        // Start observing updates - capture syncServiceContainer and syncCoordinator
        healthKitManager.startObservingHealthKitUpdates { [syncServiceContainer, syncCoordinator] in
            // Callback when new data arrives
            print("🔔 HealthKit data update detected, triggering sync")
            
            guard let syncService = syncServiceContainer.syncService else {
                print("⚠️ SyncService not initialized yet")
                return
            }
            
            // Request sync through coordinator (coalesces multiple rapid requests)
            Task {
                await syncCoordinator.requestSync {
                    await syncService.syncNow()
                }
            }
        }
        
        print("✅ HealthKit observers started")
    }
    
}

// Container class to hold SyncService and make it accessible in closures
@MainActor
class SyncServiceContainer: ObservableObject {
    @Published var syncService: SyncService?
    
    func initialize(healthKitManager: HealthKitManager, apiClient: ApiClient) {
        syncService = SyncService(healthKitManager: healthKitManager, apiClient: apiClient)
        print("✅ SyncService initialized")
    }
}
