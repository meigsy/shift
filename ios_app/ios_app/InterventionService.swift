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
        let path = "/interventions?user_id=\(userId)&status=created"
        
        do {
            let data = try await apiClient.get(path: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(InterventionsResponse.self, from: data)
            return response.interventions
        } catch {
            print("❌ Error fetching interventions: \(error.localizedDescription)")
            throw error
        }
    }
}
