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
        let queryItems = [
            URLQueryItem(name: "user_id", value: userId),
            URLQueryItem(name: "status", value: "created")
        ]
        
        let response: InterventionsResponse = try await apiClient.get(
            path: "/interventions",
            queryItems: queryItems
        )
        
        return response.interventions
    }
}
