//
//  ios_appApp.swift
//  ios_app
//
//  Created by Sylvester Meighan on 11/25/25.
//

import SwiftUI

@main
struct ios_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    // Shared instances
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var syncServiceContainer = SyncServiceContainer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .onAppear {
                    // Initialize syncService with healthKitManager
                    syncServiceContainer.initialize(healthKitManager: healthKitManager)
                    
                    // Start observing HealthKit updates after app appears
                    Task { @MainActor in
                        await setupHealthKitObservers()
                    }
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
        
        // Start observing updates - capture syncServiceContainer to access syncService
        healthKitManager.startObservingHealthKitUpdates { [syncServiceContainer] in
            // Callback when new data arrives
            print("🔔 HealthKit data update detected, triggering sync")
            
            guard let syncService = syncServiceContainer.syncService else {
                print("⚠️ SyncService not initialized yet")
                return
            }
            
            // Request background task and perform sync
            Task { @MainActor in
                await performSyncWithBackgroundTask(syncService: syncService)
            }
        }
        
        print("✅ HealthKit observers started")
    }
    
    @MainActor
    private func performSyncWithBackgroundTask(syncService: SyncService) async {
        let application = UIApplication.shared
        
        // Request background task
        var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
        
        backgroundTaskIdentifier = application.beginBackgroundTask(withName: "HealthKitSync") {
            // Task expired
            print("⏱️ Background task expired")
            if backgroundTaskIdentifier != .invalid {
                application.endBackgroundTask(backgroundTaskIdentifier)
                backgroundTaskIdentifier = .invalid
            }
        }
        
        guard backgroundTaskIdentifier != .invalid else {
            print("⚠️ Could not start background task")
            return
        }
        
        print("🔄 Starting background sync task")
        
        // Perform sync
        do {
            try await syncService.syncNewHealthData()
            print("✅ Background sync completed")
        } catch {
            print("❌ Background sync failed: \(error.localizedDescription)")
        }
        
        // End background task
        if backgroundTaskIdentifier != .invalid {
            application.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }
}

// Container class to hold SyncService and make it accessible in closures
@MainActor
class SyncServiceContainer: ObservableObject {
    var syncService: SyncService?
    
    func initialize(healthKitManager: HealthKitManager) {
        syncService = SyncService(healthKitManager: healthKitManager)
        print("✅ SyncService initialized")
    }
}
