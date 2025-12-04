//
//  InterventionService.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import Foundation

@MainActor
class InterventionService {
    private let apiClient: ApiClient
    
    init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }
    
    func fetchPendingInterventions(userId: String) async throws -> [Intervention] {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        // Build query string with proper encoding
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "status", value: "created")
        ]
        
        guard let queryString = components.percentEncodedQuery else {
            throw ApiError.invalidURL
        }
        
        let path = "/interventions?\(queryString)"
        print("🌐 [\(timestamp)] Fetching interventions from: \(path)")
        
        do {
            let data = try await apiClient.get(path: path)
            let response = try JSONDecoder().decode(InterventionsResponse.self, from: data)
            print("✅ [\(timestamp)] Fetched \(response.interventions.count) intervention(s)")
            return response.interventions
        } catch let error as DecodingError {
            print("❌ [\(timestamp)] Failed to decode interventions response: \(error)")
            throw error
        } catch {
            print("❌ [\(timestamp)] Error fetching interventions: \(error.localizedDescription)")
            throw error
        }
    }
    
    func updateInterventionStatus(_ interventionInstanceId: String, status: String) async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        let path = "/interventions/\(interventionInstanceId)/status"
        let body = ["status": status]
        
        print("🌐 [\(timestamp)] Updating intervention \(interventionInstanceId) status to: \(status)")
        
        do {
            let _ = try await apiClient.patch(path: path, body: body)
            print("✅ [\(timestamp)] Successfully updated intervention status")
        } catch {
            print("❌ [\(timestamp)] Error updating intervention status: \(error.localizedDescription)")
            throw error
        }
    }
}


