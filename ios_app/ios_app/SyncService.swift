//
//  SyncService.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation
import UIKit

extension Notification.Name {
    static let healthDataSyncCompleted = Notification.Name("healthDataSyncCompleted")
    static let contextRefreshNeeded = Notification.Name("contextRefreshNeeded")
}

@MainActor
class SyncService {
    
    private let healthKitManager: HealthKitManager
    private let apiClient: ApiClient
    private let lastSyncKey = "com.shift.ios-app.lastSyncTimestamp"
    
    init(healthKitManager: HealthKitManager, apiClient: ApiClient) {
        self.healthKitManager = healthKitManager
        self.apiClient = apiClient
    }
    
    func updateToken(_ token: String?) {
        apiClient.setToken(token)
    }
    
    // MARK: - Sync State Management
    
    /// Get the last successful sync timestamp, or default to 7 days ago
    func lastSyncTimestamp() -> Date {
        if let timestamp = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            return timestamp
        }
        // Default to 7 days ago for first sync
        return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }
    
    /// Update the last successful sync timestamp
    private func updateLastSyncTimestamp(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastSyncKey)
    }
    
    // MARK: - Sync Logic
    
    /// Request a sync (fire-and-forget)
    /// Simply triggers the sync process with background task management
    func requestSync() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.performSyncWithBackgroundTask()
        }
    }
    
    /// Perform sync immediately (called by SyncCoordinator)
    /// This is the actual sync work that SyncCoordinator orchestrates
    func syncNow() async {
        await performSyncWithBackgroundTask()
    }
    
    /// Perform sync with background task management
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
        do {
            try await syncNewHealthData()
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
    
    /// Sync new health data since last sync timestamp
    private func syncNewHealthData() async throws {
        
        let lastSync = lastSyncTimestamp()
        let now = Date()
        
        print("🔄 Starting sync: fetching data since \(lastSync)")
        
        // Fetch all data since last sync
        let batch = await healthKitManager.fetchAllDataSince(lastSync)
        
        guard batch.totalSampleCount > 0 else {
            print("ℹ️ No new data to sync")
            return
        }
        
        print("📦 Fetched \(batch.totalSampleCount) samples, posting to backend...")
        
        // POST to backend
        try await postHealthDataBatch(batch)
        
        // Update last sync timestamp on success
        updateLastSyncTimestamp(now)
        print("✅ Sync successful, updated timestamp to \(now)")
        
        // Notify that sync completed (for UI refresh)
        NotificationCenter.default.post(name: .healthDataSyncCompleted, object: nil)
    }
    
    // MARK: - HTTP POST
    
    /// POST HealthDataBatch to backend endpoint using authenticated ApiClient
    private func postHealthDataBatch(_ batch: HealthDataBatch) async throws {
        print("📤 POSTing health data batch to /watch_events")
        
        do {
            // Use ApiClient for authenticated request
            let _ = try await apiClient.post(path: "/watch_events", body: batch)
            print("✅ POST successful")
        } catch ApiError.unauthorized {
            print("❌ Authentication failed - token expired or invalid")
            throw SyncError.unauthorized
        } catch ApiError.httpError(let statusCode, let message) {
            print("❌ Backend returned status \(statusCode): \(message)")
            throw SyncError.httpError(statusCode: statusCode, body: message)
        } catch {
            print("❌ POST failed: \(error.localizedDescription)")
            throw SyncError.httpError(statusCode: 0, body: error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, body: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized - please sign in again"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        }
    }
}

