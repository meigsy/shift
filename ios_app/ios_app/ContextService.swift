//
//  ContextService.swift
//  ios_app
//
//  Fetches the /context payload from the SHIFT backend.
//

import Foundation

@MainActor
class ContextService {
    private let apiClient: ApiClient
    
    init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }
    
    func fetchContext() async throws -> ContextPayload {
        // Backend derives user identity from auth token only; no user_id param needed
        let path = "/context"
        let data = try await apiClient.get(path: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContextPayload.self, from: data)
    }
}
