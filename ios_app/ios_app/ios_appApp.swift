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
    @State private var syncService: SyncService?
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .task {
                    // Initialize sync service
                    syncService = SyncService(healthKitManager: healthKitManager)
                    
                    // Start observing HealthKit updates after app launches
                    await setupHealthKitObservers()
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
        
        // Start observing updates
        healthKitManager.startObservingHealthKitUpdates { [weak self] in
            // Callback when new data arrives
            guard let self = self else { return }
            
            print("🔔 HealthKit data update detected, triggering sync")
            
            // Request background task and perform sync
            Task { @MainActor in
                await self.performSyncWithBackgroundTask()
            }
        }
        
        print("✅ HealthKit observers started")
    }
    
    @MainActor
    private func performSyncWithBackgroundTask() async {
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
        guard let syncService = syncService else {
            print("⚠️ SyncService not initialized")
            if backgroundTaskIdentifier != .invalid {
                application.endBackgroundTask(backgroundTaskIdentifier)
            }
            return
        }
        
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
