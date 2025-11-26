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
    private let endpointURL = URL(string: "https://api.shift.example.com/watch_events")!
    private let lastSyncKey = "com.shift.ios-app.lastSyncTimestamp"
    
    init(healthKitManager: HealthKitManager) {
        self.healthKitManager = healthKitManager
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
    
    /// POST HealthDataBatch to backend endpoint
    private func postHealthDataBatch(_ batch: HealthDataBatch) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encode batch to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        let jsonData = try encoder.encode(batch)
        request.httpBody = jsonData
        
        print("📤 POSTing \(jsonData.count) bytes to \(endpointURL)")
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Backend returned status \(httpResponse.statusCode): \(errorBody)")
            throw SyncError.httpError(statusCode: httpResponse.statusCode, body: errorBody)
        }
        
        print("✅ POST successful (status \(httpResponse.statusCode))")
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body)"
        }
    }
}

