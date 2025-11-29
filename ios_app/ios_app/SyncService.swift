//
//  SyncService.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation

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
    
    /// Sync new health data since last sync timestamp
    func syncNewHealthData() async throws {
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

